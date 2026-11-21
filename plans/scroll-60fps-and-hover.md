# Scroll: show the scroll before the repaint, and make hover cheap

Follows the `browser.trace` analysis of 2026-11-15 (long-page scroll plus `#` fragment links). That trace scrolled at **50–52 fps**, not 60.

Data:
- `browser.trace` (GUI, 44 s, 1,030 `BrowserTab.scrollAt` events, 60 Hz display).
- `ToyStackHeadless` (release) on a local copy of `https://browser.engineering/reflow.html` (1,773 blocks, about the same size as the page in the trace), 1440×712. Scroll: 240 events of 150 px, one per tick (the trace averaged ~150 px per event). 3 runs per variant, 90 scroll repaints.
- `sample` (macOS) during a 4,400-event scroll loop and during 3,000 hit tests.
- Hover cost was measured with a headless-only hook (a temporary `--hover-at` flag and a shorter idle wait in `ScenarioRunner`). The hook was added to both copies below and is **not** part of this plan, see §6.1.

No code in the repo was changed. The diff and code blocks of §4 were applied **as written** with `patch` to a fresh `rsync` of HEAD `2b64bfe` (`/tmp/ts-verify`). The baseline for timings is HEAD plus the Step 3 span only (`/tmp/ts-headv`), because without the span the hover check cannot be timed. Results are in §3.

## 1. Summary

| Problem | Before | After | Step |
|---|---:|---:|---|
| Scroll events that wait for a repaint before anything moves on screen | 127 of 1,030; 21 ms p50, 33 ms max to show | shown in the same event when the painted content still covers the viewport | 1 |
| Hit test, pointer near the top of the page (headless) | 9.6 ms | 2.7 ms | 2 |
| Hit test, middle / bottom of the page | 6.3 / 2.4 ms | 2.0 / 0.9 ms | 2 |
| Scene build of one scroll repaint (`paint.scene.build`, headless) | 3.85–3.92 ms | 3.26–3.30 ms | 2 |
| Hover that changes which elements are hovered (headless) | 42–67 ms, then 17–20 ms each | 13–28 ms, then 6–9 ms each | 3–4 |
| Moving the pointer out of two `:hover` ancestors at once | descendant keeps its hover style | descendant restyled | 4 |

## 2. Analysis

### 2.1 A scroll that needs a repaint is not shown until the repaint is done

`Frame` paints a window of the page: the viewport plus 2 viewport heights above and below (`windowForScroll`, `Frame.swift:1064-1070`). When the viewport comes within half a viewport of either edge of that window, `scrollNeedsPaint()` returns true (`Frame.swift:1072-1079`, `1585-1587`).

`Browser.applyScroll` (`Browser.swift:743-768`) then stops:

```swift
if needsPaint {
    pendingScrollTarget = scroll
    needsScrollPaint = true
    needsAnimationFrame = true
    return
}
```

It does not present the new scroll position. The repaint runs on the next animation tick (`Browser.swift:261-271`), then the tiles are drawn, and only then does the page move. In the trace:

| Scroll events without an immediate present | Count | Time until the next present |
|---|---:|---|
| waiting for a repaint | 127 | 20.9 ms p50, 32.9 ms max |
| waiting for new tiles only | 94 | 2.6 ms p50 |
| other | 10 | 2.1 ms p50 |

The 127 are the frames that miss a vsync. At the moment the repaint is requested, the old painted list still holds the whole viewport: the margin is half a viewport (356 px at 712 px), and the trace moved ~150 px per event. So the old list can show this scroll while the repaint waits for the next tick.

### 2.2 The 50–110 ms hover pauses come from rebuilding the style snapshot, not from the hit test

In the first analysis I guessed that the hit test caused these pauses. Timing the whole hover check (`resolveHover`, `Frame.swift:1809-1826`) in the headless runner shows it is something else:

| Pointer move | Hover check |
|---|---:|
| hovered elements change (4–5 elements enter or leave) | 36–72 ms |
| hovered elements stay the same (hit test only) | 3–5 ms |

`setHoveredElements` (`Frame.swift:1828-1859`) calls `markHoverDescendants` once for every element that entered or left. Each call (`Frame.swift:2088-2114`) builds **two** snapshots of the whole document with `StyleSnapshotBuilder.build` (`StyleSnapshotBuilder.swift:14`): ~3.5 ms each on this page, plus a walk of the element's subtree. Five changed elements means ten snapshots. `book.css` has rules like `x:hover y`, so this path runs on every move between paragraphs.

The same code has a correctness bug. For each changed element it flips **only that element's** hover flag back, so each match is computed in a mixed state that never existed on screen. Take this rule:

```css
#outer:hover #inner:hover #styled { color: red; }
```

When the pointer leaves both `#outer` and `#inner` in one move, neither "only `#outer` is back" nor "only `#inner` is back" matches `#styled`. So `#styled` is never marked and stays red. Matching once against the state before the move and once against the state after the move finds every descendant whose rule can change. It also needs only two snapshots per move.

### 2.3 The hit test and the scene build repeat work for every line

`sample` during 3,000 hit tests (`LayoutTree.hitTest`, `LayoutPaintPass.swift:10-54`):

| Function | % of hit test |
|---|---:|
| `LayoutTree.currentInlineBoxes` | 72.7 |
| … `LayoutTree.textTextWidth` | 41.7 |
| … array allocation (`_createNewBuffer`, `_consumeAndCreateNew`) | 30.1 |
| `LayoutTree.paintOrder` | 10.8 |

`currentInlineBoxes` (`LineLayoutPass.swift:372-393`) checks every box of a line against its text node. For each box it:

1. calls `textTextWidth(child)` (`TextLayoutPass.swift:116-129`), which builds a new list of the line's children just to find this child's position, so a line with *n* words costs *n²* steps plus *n* arrays;
2. compares `inlineText(box) == textString(child)`. When both fragments are equal, both strings come from the same `TextRun` with the same start and count (`LayoutTree.swift:1058-1064`, `1089-1094`), so they are always equal. The comparison still builds two `String`s and runs Unicode normalization (`_NFCNormalizer`, `_stringCompareSlow` in the profile).

The hit test walks the children in reverse order and stops at the first hit. A pointer near the **top** of the page therefore visits almost every line of the document, which is why it costs 9.6 ms at scroll 0 and 2.4 ms at the bottom.

The scroll repaint calls the same `currentInlineBoxes` for each line in the painted window (`PaintSceneBuilder.swift:59`), where it was 21 % of `paint.scene.build`.

## 3. Verification in the temporary copy

| Run | Result |
|---|---|
| HEAD + the tests of §4, `swift test --filter "ScrollRepaintPresentTests\|HoverTests\|HoverTraceTests"` | 3 failures, each for the intended reason: `activeTabScroll → 0.0 == target → 1190.0`; `begins → 0 == 1`; `#styled` color `red == black`. `scrollPastThePaintedContentWaitsForTheRepaint` and `enteringTwoHoveredAncestorsAtOnceStylesTheirDescendant` pass on HEAD (they guard behavior that must not change). |
| All steps, `swift test --no-parallel` | 441 tests pass |
| All steps, `swift test` (parallel), 4 runs | `ResizeLayoutStartTests.syncLayoutResizeWaitsForTheTick` failed in 3 of 4 runs, nothing else failed |
| HEAD, `swift test` (parallel), 6 runs | the same test failed in 4 of 6 runs. It depends on wall-clock frame timing, and [resize-layout-closure-copies.md](resize-layout-closure-copies.md) §3 records the same failure on HEAD |

Headless measurements (release, local `reflow.html`, 1440×712). Two rounds; each scroll round is 3 runs with 30 scroll repaints each:

| Variant | `paint.scene.build` p50 | `paint.pass` p50 | `BrowserTab.paint` p50 | Hit test p50 at scroll 0 / 15,000 / 35,000 |
|---|---:|---:|---:|---|
| HEAD | 3.92 / 3.85 ms | 0.94 ms | 5.10 / 5.03 ms | 9.59 / 6.34 / 2.36 ms |
| All steps | 3.26 / 3.30 ms | 0.96–0.97 ms | 4.46 / 4.49 ms | 2.76 / 2.00 / 0.93 ms |

In an earlier session, the string-comparison part of Step 2 alone brought the hit test at scroll 0 from 9.6 to 4.2 ms. The width lookup did the rest.

Hover check (`BrowserTab.hover`) for the same 10 pointer moves, two rounds:

| Variant | First three moves (new chain at the top of the page) | Next seven moves |
|---|---|---|
| HEAD + Step 3 span | 44.0–44.2, 66.6–67.3, 42.1–42.7 ms | 17.2–20.1 ms |
| All steps | 12.9, 27.3–27.8, 27.3–28.5 ms | 6.4–8.9 ms |

After all steps, most of the 6–9 ms left is the two style snapshots of Step 4 (~3.5 ms each on this page). The hit test is another ~1–3 ms.

Step 1 changes when the GUI presents, and `ToyStackHeadless` has no presenter (`profiling.md`, "Known distortions"). Its effect is proven by the test in Step 1, not by a headless number. The expected GUI effect is [INFERENCE]: those of the 127 events in §2.1 that go through `applyScroll` move on screen in the same event, because one event moves ~150 px and the margin is 356 px.

## 4. Plan

### Files that change

| File | Step | Why |
|---|---|---|
| `Tests/ToyStackTests/Core/ScrollRepaintPresentTests.swift` (new) | 1 | `Browser.applyScroll` is in `Core` |
| `Sources/Engine/Core/Frame.swift` | 1, 3, 4 | painted-window check; hover span; hover snapshots |
| `Sources/Engine/Core/Browser.swift` | 1 | present the scroll while the repaint waits |
| `Sources/Engine/Layouts/LineLayoutPass.swift` | 2 | `currentInlineBoxes` without rebuilt lists and strings |
| `Sources/Engine/Layouts/TextLayoutPass.swift` | 2 | width lookup by position |
| `Tests/ToyStackTests/Diagnostic/HoverTraceTests.swift` (new) | 3 | trace output belongs in `Diagnostic` |
| `profiling.md` | 3 | new span |
| `Tests/ToyStackTests/Core/HoverTests.swift` | 4 | hover invalidation is done in `Frame` |

### Design decisions

**Step 1: what to do with a scroll that needs a repaint**

- **Option A (recommended): present it now if the old painted list still covers the viewport, and repaint on the next tick as today.** A small change, and the next tick does the same work as before. Trade-off: if the next scroll leaves the painted window before the repaint lands, that scroll waits, as all such scrolls do today.
- Option B: repaint inside the scroll event itself. The page is always correct immediately, but the event takes the whole repaint (8.5 ms p50 in the GUI trace), so the next scroll event arrives late. That is the stutter we are removing.
- Option C: paint a larger window (more overscan). Repaints become rarer, but the display list and every composite get bigger, and the wait in §2.1 still happens, just less often.

**Step 4: how to find descendants that hover may restyle**

- **Option A (recommended): one snapshot before the pointer move and one after, then match each changed subtree against both.** Two snapshots per move instead of two per changed element. This also fixes the mixed-state bug, because the two snapshots are the real before and after states.
- Option B: keep one snapshot and change only the hover flags inside it. This saves one more snapshot (~3.5 ms of the 6–9 ms left per move, §3), but `StyleSnapshot` would need a new way to modify it in place, and other code relies on snapshots never changing.

### Step 1: scroll moves on screen before the repaint

Write the test first. New file `Tests/ToyStackTests/Core/ScrollRepaintPresentTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ScrollRepaintPresentTests {
    @Test func scrollNearTheEndOfThePaintedContentShowsBeforeTheRepaint() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }
        let frame: Frame = page.frame
        // The first paint at scroll 0 reaches three viewport heights down, so
        // this offset needs a repaint but every pixel it shows is painted.
        let target: CGFloat = 2 * frame.frameHeight - 10
        try #require(frame.maxScroll > target)

        page.scroll(by: target)

        #expect(frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == target)

        page.browser.advanceFrame()

        #expect(!frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == target)
    }

    @Test func scrollPastThePaintedContentWaitsForTheRepaint() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }
        let frame: Frame = page.frame
        let target: CGFloat = frame.maxScroll
        try #require(target > 4 * frame.frameHeight)

        page.scroll(by: target)

        #expect(frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == 0)

        page.browser.advanceFrame()

        #expect(!frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == target)
    }
}

// MARK: - ScrollTestBrowser

@MainActor
private struct ScrollTestBrowser {
    let browser: Browser
    let frame: Frame
    let paths: [String]

    static func open() async throws -> ScrollTestBrowser {
        let id: String = UUID().uuidString
        let tracePath: String = NSTemporaryDirectory() + "scroll-repaint-\(id).trace"
        let pagePath: String = NSTemporaryDirectory() + "scroll-repaint-\(id).html"
        let html: String = #"<p>start</p><div style="height: 6000px"></div><p>end</p>"#
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)

        let browser: Browser = Browser(tracePath: tracePath)
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()

        let tab: BrowserTab = try #require(browser.activeTab)
        try #require(await pump({ tab.isLoaded }))
        try #require(await settle(browser, until: { !tab.rootFrame.displayList.isEmpty }))
        return ScrollTestBrowser(browser: browser, frame: tab.rootFrame, paths: [tracePath, pagePath])
    }

    func scroll(by offset: CGFloat) {
        browser.activeTab?.scrollBy(deltaY: -offset * browser.pageZoom)
    }

    func close() {
        browser.stopAnimationTimer()
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private static func settle(_ browser: Browser, until condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            browser.advanceFrame()
            _ = await pump({ browser.isRenderIdle })
            if browser.isRenderIdle, condition() {
                return true
            }
        }
        return false
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }
}
```

The `<p>start</p>` matters: without visible content at the top, the painted list is empty and `settle` waits forever.

Run `swift test --filter ScrollRepaintPresentTests`. Expected: `scrollNearTheEndOfThePaintedContentShowsBeforeTheRepaint` **fails** with `(page.browser.activeTabScroll → 0.0) == (target → 1190.0)`. `scrollPastThePaintedContentWaitsForTheRepaint` passes; it guards the case where showing the scroll would show unpainted content.

`Sources/Engine/Core/Frame.swift`:

```diff
@@ -1069,11 +1069,10 @@
         )
     }
 
-    private func viewportFitsInPaintedWindow() -> Bool {
+    private func viewportFitsInPaintedWindow(margin: CGFloat) -> Bool {
         let window: PaintWindow = state.display.painted.window
         guard window != .full else { return true }
 
-        let margin: CGFloat = frameHeight / 2
         return scroll >= window.top + margin
             && scroll + frameHeight <= window.bottom - margin
     }
@@ -1573,7 +1572,7 @@
 
     @discardableResult
     func repaintForScroll() -> Bool {
-        guard !viewportFitsInPaintedWindow() else { return false }
+        guard !viewportFitsInPaintedWindow(margin: frameHeight / 2) else { return false }
 
         state.display.paint.isNeeded = true
         state.display.composite.isNeededForPaint = true
@@ -1583,9 +1582,13 @@
     }
 
     func scrollNeedsPaint() -> Bool {
-        return !viewportFitsInPaintedWindow()
+        return !viewportFitsInPaintedWindow(margin: frameHeight / 2)
     }
 
+    func paintedWindowCoversViewport() -> Bool {
+        return viewportFitsInPaintedWindow(margin: 0)
+    }
+
     private func scrollTo(_ elt: DOMRef) {
         state.runtime.animation.tween = nil
         guard let doc = document else { return }
```

`Sources/Engine/Core/Browser.swift`:

```diff
@@ -741,16 +741,18 @@
     }
 
     public func applyScroll(_ scroll: CGFloat) {
-        let needsPaint: Bool = activeTab?.rootFrame.scrollNeedsPaint() ?? false
-        if needsPaint {
+        let frame: Frame? = activeTab?.rootFrame
+        if frame?.scrollNeedsPaint() == true {
             pendingScrollTarget = scroll
             needsScrollPaint = true
             needsAnimationFrame = true
-            return
+            // The repaint waits for the next tick. Until then the painted list
+            // still holds everything the viewport shows, so show this scroll now.
+            guard frame?.paintedWindowCoversViewport() == true else { return }
+        } else {
+            needsScrollPaint = false
+            pendingScrollTarget = nil
         }
-
-        needsScrollPaint = false
-        pendingScrollTarget = nil
         activePresentation.scroll.scroll = scroll
 
         if activePresentation.render.content.usesSublayers {
```

`needsScrollPaint` stays true, so the next `animationTick` still runs `repaintForScroll` (`Browser.swift:261-271`), which commits the new list. `applyScrollAndUpdateInterest` (`Browser.swift:770-786`) keeps its early return. It only runs when the viewport leaves the interest region (`checkInterestRegion`, `Frame.swift:1789-1801`), and the trace cannot tell which of the two functions the 127 waiting events in §2.1 went through. If a trace taken after this step still shows scroll events waiting for `BrowserTab.paint` while the viewport is inside the painted window, the same guard belongs there too.

Run `swift test --filter "ScrollRepaintPresentTests|PaintCullingTests"`: 8 tests pass.

Commit:

```
perf: scrolling no longer freezes while the page repaints

A scroll that came near the end of the painted part of the page was not
shown until the repaint finished on the next tick, so those frames
reached the screen 21-33 ms late. The old painted content still covers
the viewport at that point, so present the scroll right away and let
the repaint follow on the tick.
```

### Step 2: checking a line's boxes without rebuilding lists and strings

No new test in this step. What it returns does not change, only the work it takes to compute it, and a test that measures time would fail randomly. The existing tests that call `currentInlineBoxes` or depend on it guard the change: `InlineBoxTests`, `LineBoxWipeTests`, `StyleInheritanceTests`, `AsyncResizeStyleChangeTests`, `BackgroundLayoutTests`, `LayoutOracleTests`, `HoverTests`, `PaintCullingTests`. The numbers are in §3.

`Sources/Engine/Layouts/TextLayoutPass.swift`:

```diff
@@ -121,6 +121,12 @@
         guard let index: Int = inline.firstIndex(of: id) else {
             return self[text: id].metrics.width
         }
+        return textTextWidth(id, at: index, in: line)
+    }
+
+    /// `index` counts the text and embed children of `line`, the order
+    /// `inlineWidths` was recorded in.
+    func textTextWidth(_ id: LayoutID, at index: Int, in line: LayoutID) -> CGFloat {
         let widths: [CGFloat] = self[line: line].content.inlineWidths
         if index < widths.count {
             return widths[index]
```

`Sources/Engine/Layouts/LineLayoutPass.swift`:

```diff
@@ -376,19 +376,28 @@
         guard let block, let revision: UInt64 = boxRevision(block),
             data.paint.boxRevision == revision
         else { return nil }
-        let children: [LayoutID] = childrenIDs(of: id).filter({ isText($0) })
-        if children.isEmpty { return data.content.boxes }
-        guard children.count == data.content.boxes.count else { return nil }
-        for (box, child) in zip(data.content.boxes, children) {
+        let inline: [LayoutID] = childrenIDs(of: id).filter({ isText($0) || isEmbed($0) })
+        let textIndices: [Int] = inline.indices.filter({ isText(inline[$0]) })
+        if textIndices.isEmpty { return data.content.boxes }
+        guard textIndices.count == data.content.boxes.count else { return nil }
+        for (box, index) in zip(data.content.boxes, textIndices) {
+            let child: LayoutID = inline[index]
             let text: TextData = self[text: child]
             guard box.dom == domID(of: child),
                 box.fragment == text.fragment,
                 box.geometry.x == x(child),
                 box.geometry.y + y(id) == textAbsoluteY(child),
-                box.geometry.width == textTextWidth(child),
-                inlineText(box) == textString(child)
+                box.geometry.width == textTextWidth(child, at: index, in: id),
+                readsTextRun(box) || inlineText(box) == textString(child)
             else { return nil }
         }
         return data.content.boxes
     }
+
+    /// Two equal fragments read the same characters from the same run, so
+    /// only a box without a run still has to compare its text.
+    private func readsTextRun(_ box: InlineBox) -> Bool {
+        guard let fragment: TextFragment = box.fragment else { return false }
+        return textRuns[fragment.block] != nil
+    }
 }
```

Why this returns exactly what it returned before:

- `index` is the child's position among the line's text **and** embed children, which is what `textTextWidth(child)` found with `firstIndex(of:)`. The guard `!data.content.hasEmbed` is not enough on its own: `placeEmbed` (`BlockLayoutPass.swift:1198-1200`) only sets it on a line that already exists, so a line that starts with an embed can have it false. That is why `inline` keeps embeds.
- The string comparison is skipped only when the box has a fragment **and** that run exists. The text node then has the same fragment (checked one line above) and reads the same run. Without a run, both strings fall back to their payloads, which can differ, so they are still compared.

Run `swift build` then `swift test`: everything passes.

Commit:

```
perf: hovering and scrolling long pages does less work per line

Checking whether a line's text boxes were still current rebuilt the
list of the line's children once per word and compared two strings
that come from the same text run. The hover hit test runs this check
for almost every line when the pointer is near the top of the page
(9.6 ms on reflow.html). Look widths up by position and skip the
comparison when both sides read the same run: 2.7 ms.
```

### Step 3: the trace shows the hover check

Write the test first. New file `Tests/ToyStackTests/Diagnostic/HoverTraceTests.swift`:

```swift
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct HoverTraceTests {
    /// Only a render with a pointer move waiting runs the hover check, so only
    /// that render may write the span; a span on every frame would hide it.
    @Test func onlyARenderAfterAPointerMoveTracesTheHoverCheck() throws {
        let path: String = NSTemporaryDirectory() + "hover-trace-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">content</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                """
        )
        let browser: Browser = Browser(tracePath: path)
        page.tab.browser = browser

        page.frame.setNeedsRender()
        page.frame.render()
        page.tab.hover(x: 10, y: 10)
        page.frame.render()
        page.frame.render()
        browser.measure.close()

        let trace: String = try String(contentsOfFile: path, encoding: .utf8)
        let begins: Int = trace.components(
            separatedBy: #""ph": "B", "cat": "input", "name": "BrowserTab.hover""#
        ).count - 1
        #expect(begins == 1)
    }
}
```

Run `swift test --filter HoverTraceTests`. Expected: **fails** with `(begins → 0) == 1`.

`Sources/Engine/Core/Frame.swift`. The span goes after the `guard`, so a render without a pointer move writes nothing. `start`/`stop` instead of `measure.span { }`, because the hover check must also run when `browser` is `nil`, as it is in `LayoutTestPage`:

```diff
@@ -1813,6 +1813,9 @@
         else { return }
         tab?.pendingHover = nil
 
+        browser?.measure.start("BrowserTab.hover", category: .input)
+        defer { browser?.measure.stop("BrowserTab.hover") }
+
         var chain: [NodeID] = []
         var current: DOMRef? = doc.hitTest(doc.rootID, x: pending.x, y: pending.y + scroll)
             .map({ DOMRef(id: $0.dom, dom: doc.dom) })
```

`profiling.md`:

```diff
@@ -164,3 +164,3 @@
 | `frame` | `composite_raster_and_draw`, `BrowserTab.anim*`, `BrowserTab.raf` |
-| `input` | `BrowserTab.scroll*` |
+| `input` | `BrowserTab.scroll*`, `BrowserTab.hover` (explicit category) |
 | `engine` | everything else, including accessibility timers |
@@ -393,3 +393,4 @@
 | `BrowserTab.paint` | main | display-list build |
 | `BrowserTab.scrollAt`, `.scrollBy` | main | input dispatch |
+| `BrowserTab.hover` | main | pointer move: hit test, hover flags, and marking hover-styled descendants; only on a render with a pending move |
 | `BrowserTab.load*` | main, awaits | load envelope |
```

Run `swift test --filter "HoverTraceTests|HoverTests"`: all pass.

Commit:

```
feat: the trace shows how long a pointer move takes

Pointer moves ran their hit test and hover restyling inside the
animation frame with no span, so a 50-110 ms pause showed up as an empty
gap. Wrap that work in a `BrowserTab.hover` span; it is only written
when a move was waiting.
```

### Step 4: a pointer move builds two style snapshots, not two per element

Write the tests first. `Tests/ToyStackTests/Core/HoverTests.swift`:

```diff
@@ -221,6 +221,55 @@
         #expect(label.style.computed.text.color == BrowserColor(cssName: "black"))
     }
 
+    @Test func enteringTwoHoveredAncestorsAtOnceStylesTheirDescendant() throws {
+        let page: LayoutTestPage = nestedHoverPage()
+        let pointer: ElementRef = try #require(page.firstElement(id: "pointer"))
+        let styled: ElementRef = try #require(page.firstElement(id: "styled"))
+        let point: CGPoint = center(try bounds(pointer, in: page))
+
+        page.tab.hover(x: point.x, y: point.y)
+        page.frame.render()
+        page.frame.render()
+
+        #expect(!styled.isHovered)
+        #expect(styled.style.computed.text.color == BrowserColor(cssName: "red"))
+    }
+
+    @Test func leavingTwoHoveredAncestorsAtOnceRestoresTheirDescendant() throws {
+        let page: LayoutTestPage = nestedHoverPage()
+        let pointer: ElementRef = try #require(page.firstElement(id: "pointer"))
+        let styled: ElementRef = try #require(page.firstElement(id: "styled"))
+        let outside: ElementRef = try #require(page.firstElement(id: "outside"))
+        let inside: CGPoint = center(try bounds(pointer, in: page))
+        let away: CGPoint = center(try bounds(outside, in: page))
+
+        page.tab.hover(x: inside.x, y: inside.y)
+        page.frame.render()
+        page.frame.render()
+        #expect(styled.style.computed.text.color == BrowserColor(cssName: "red"))
+
+        page.tab.hover(x: away.x, y: away.y)
+        page.frame.render()
+        page.frame.render()
+
+        #expect(styled.style.computed.text.color == BrowserColor(cssName: "black"))
+    }
+
+    private func nestedHoverPage() -> LayoutTestPage {
+        return LayoutTestPage(
+            html: """
+                <div id="outer"><div id="inner"><div id="pointer">pointer</div><div id="styled">styled</div></div></div>
+                <div id="outside">outside</div>
+            """,
+            rules: """
+                html { width: 600px; }
+                body { display: block; }
+                div { display: block; }
+                #outer:hover #inner:hover #styled { color: red; }
+            """
+        )
+    }
+
     @Test func hitTestUsesTheLayoutFromTheSameFrame() throws {
         let page: LayoutTestPage = LayoutTestPage(
             html: #"<div id="box">content</div>"#,
```

Run `swift test --filter HoverTests`. Expected: `leavingTwoHoveredAncestorsAtOnceRestoresTheirDescendant` **fails** with `#styled` still `red`. `enteringTwoHoveredAncestorsAtOnceStylesTheirDescendant` passes on HEAD. It keeps the entering case correct when the snapshots change.

`Sources/Engine/Core/Frame.swift` (line numbers are HEAD's, before Step 3):

```diff
@@ -1830,6 +1830,8 @@
         let leaving: Set<NodeID> = Set(state.runtime.interaction.hovered)
         guard entering != leaving else { return }
 
+        let selectors: [any CSSSelector] = state.document.sheets.index.list.index.hoverAncestorSelectors
+        let before: StyleSnapshot? = selectors.isEmpty ? nil : StyleSnapshotBuilder.build(root: nodes)
         var changed: [NodeID] = []
         for element in state.runtime.interaction.hovered where !entering.contains(element) {
             dom.setFlag(\.isHovered, false, of: element)
@@ -1842,19 +1844,16 @@
         }
         state.runtime.interaction.hovered = chain
 
+        for element in changed {
+            noteStyleInvalidation("style.invalidate.hover.node")
+            setNeedsStyle(dom.ref(element))
+        }
+
         // A descendant (e.g. `li:hover span`) can be styled by an ancestor
         // that is still hovered after the descendant left the chain.
         // On exit that ancestor is the only path back to the descendant.
-        for element in changed {
-            let ref: DOMRef = dom.ref(element)
-            if state.document.sheets.index.list.index.hoverStylesDescendants {
-                noteStyleInvalidation("style.invalidate.hover.node")
-                setNeedsStyle(ref)
-                markHoverDescendants(of: ref)
-            } else {
-                noteStyleInvalidation("style.invalidate.hover.node")
-                setNeedsStyle(ref)
-            }
+        if let before {
+            markHoverDescendants(of: changed, selectors: selectors, before: before)
         }
     }
 
@@ -2085,26 +2084,23 @@
         state.layout.tree.isDirty = true
     }
 
-    private func markHoverDescendants(of element: DOMRef) {
-        let selectors: [any CSSSelector] = state.document.sheets.index.list.index.hoverAncestorSelectors
-        guard !selectors.isEmpty else { return }
-
-        let newState: Bool = element.isHovered
+    /// Matching against the whole state before the move and the whole state
+    /// after it finds every descendant whose rule can flip, including a rule
+    /// that needs two of the changed elements hovered at the same time.
+    private func markHoverDescendants(
+        of changed: [NodeID],
+        selectors: [any CSSSelector],
+        before: StyleSnapshot
+    ) {
+        let after: StyleSnapshot = StyleSnapshotBuilder.build(root: nodes)
+        let changedSet: Set<NodeID> = Set(changed)
         var matched: [NodeID: DOMRef] = [:]
-        dom.setFlag(\.isHovered, !newState, of: element.id)
-        collectHoverMatches(
-            under: element,
-            selectors: selectors,
-            snapshot: StyleSnapshotBuilder.build(root: nodes),
-            into: &matched
-        )
-        dom.setFlag(\.isHovered, newState, of: element.id)
-        collectHoverMatches(
-            under: element,
-            selectors: selectors,
-            snapshot: StyleSnapshotBuilder.build(root: nodes),
-            into: &matched
-        )
+        for element in changed {
+            let ref: DOMRef = dom.ref(element)
+            guard !hasAncestor(ref, in: changedSet) else { continue }
+            collectHoverMatches(under: ref, selectors: selectors, snapshot: before, into: &matched)
+            collectHoverMatches(under: ref, selectors: selectors, snapshot: after, into: &matched)
+        }
 
         for node in matched.values {
             StyleInvalidation.markNode(node)
@@ -2113,6 +2109,15 @@
         noteStyleInvalidation("style.invalidate.hover.matched", by: matched.count)
     }
 
+    private func hasAncestor(_ node: DOMRef, in set: Set<NodeID>) -> Bool {
+        var current: DOMRef? = node.parent
+        while let ancestor = current {
+            if set.contains(ancestor.id) { return true }
+            current = ancestor.parent
+        }
+        return false
+    }
+
     private func collectHoverMatches(
         under element: DOMRef,
         selectors: [any CSSSelector],
```

Notes:

- The `before` snapshot is taken **before** the flags change; that is the only point where the old state still exists.
- A changed element inside another changed element is skipped. `collectHoverMatches` (`Frame.swift:2116-2138`) walks the ancestor's whole subtree, which already includes it. The hovered elements always form a chain from the pointer up to `<html>`, so without the skip the same nodes would be walked once per ancestor.
- `style.invalidate.hover.matched` is now written once per pointer move instead of once per changed element. Nothing in `Tests/` reads it.

Run `swift build` then `swift test`: everything passes.

Commit:

```
fix: moving the pointer no longer pauses or leaves hover styles behind

Each element that entered or left the hover chain rebuilt the style
snapshot of the whole document twice, so one pointer move cost 36-72 ms
on reflow.html. Each check also saw a mix of old and new hover states,
so a rule needing two hovered ancestors was never undone when the
pointer left both at once. Take one snapshot before the move and one
after, and match each changed subtree against both.
```

## 5. How to measure again

GUI: record a scroll trace as before (long page, fast trackpad scroll, a few `#` links), then:

- **Step 1:** for each `BrowserTab.scrollAt`, check whether a `present.main` starts inside it. Before: 231 of 1,030 had none, 127 of them waiting for a `BrowserTab.paint`. Expected after: only events that jump out of the painted window, such as fragment jumps, wait for the paint.
- **Steps 3–4:** `BrowserTab.hover` spans. Expected: 6–9 ms per move headless (GUI ~2× that), up to ~28 ms headless when the pointer enters the page from outside (§6.4).

Headless, for `paint.scene.build`:

```bash
swift build -c release
mkdir -p /tmp/page && cd /tmp/page
curl -sL -o reflow.html https://browser.engineering/reflow.html
for f in book.css fonts.css book.js; do curl -s -o $f https://browser.engineering/$f; done
cd -
args=(); for i in $(seq 0 239); do args+=(--scroll-at "$(echo "scale=4; 3 + $i/60" | bc):700:300:-150"); done
.build/release/ToyStackHeadless file:///tmp/page/reflow.html --trace /tmp/scroll.trace \
  --width 1440 --height 712 --frame-limit 480 "${args[@]}"
```

Read `paint.scene.build.us` and `paint.pass.us` from each `profile.paint` after the first one (the first one is the load).

## 6. Not in this plan

### 6.1 Headless gets stuck after a style pass that changes nothing

This was found while adding the temporary `--hover-at`. A hover whose hovered elements have no `:hover` rule runs a style pass that changes nothing. `commitFrame` still calls `Browser.commit`, which calls `setNeedsComposite()` (`Browser.swift:335-341`). `scheduleRasterAndDraw` then sees an unchanged `FrameSignature` and returns early (`Browser.swift:431-435`). It clears only `needsDraw`, so `needsComposite` and `needsRaster` stay true and `isRenderIdle` never becomes true again. `ToyStackHeadless` waits 10 s on every tick after that. In the GUI the leftover flags are only cleared by the next real composite. This is a separate fix with its own test; it blocks adding `--hover-at` to the headless runner.

### 6.2 The scroll repaint still rebuilds every block

After Step 2, `paint.scene.build` is ~3.3 ms headless (GUI ~2× that). 1,773 of its 1,952 nodes are blocks, and blocks are never culled (`PaintSceneBuilder.swift:107-117`). Each `PaintNode` is 1,192 bytes (`ComputedStyle` alone is 689 bytes), and copying them is 30 % of the build. Measured or considered:

| Idea | Gain | Why not now |
|---|---|---|
| Reserve node capacity from the previous scene | ~0.4 ms (3.34 → 2.92 in an earlier session, measured on top of the Step 2 string-comparison change) | needs a per-frame "last scene size" field; small |
| Skip blocks outside the window | most of the build | needs the bounds of everything a block's subtree paints (positioned and translated descendants, content taller than the block); layout does not track that |
| Reuse the scene when only the window moved | build cost gone on most scroll repaints | every change that forgets to mark paint would then show stale content |

With Step 1 the repaint is no longer what the user waits for, so these only matter if repaints start to delay the next scroll event.

### 6.3 Skipping lines in the hit test

Returning early from `hitTest` for a line whose rectangle does not contain the point measured 2.7 → 1.0 ms on top of Step 2 (earlier session; not in §3's numbers). But a text box is hit-tested down to `top + linespace` (`LayoutPaintPass.swift:37-42`), and `linespace` includes the font's leading, while the line's height is only ascent + descent (`LineLayoutPass.swift:366`). Skipping by the line's rectangle would change which element is hit in that gap, so it needs its own decision.

### 6.4 The first hover after entering the page

When the pointer enters from outside the page, `<html>` and `<body>` change, and Step 4 walks the whole document twice: 13–28 ms. Moves inside the page cost 6–9 ms.

### 6.5 Fragment jumps

A jump is one move, not an animation. It takes ~50 ms (3 frames): repaint 6.4–9.2 ms, all 132 tiles drawn again (~7 ms), and the upload spread over 2–3 presents at 4 MP each. The old content stays on screen until the upload finishes, so the screen never goes blank. Out of scope for frame rate.
