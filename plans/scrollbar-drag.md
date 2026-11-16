# Drag the page scrollbar thumb

## What is wrong

The grey bar on the right edge is only a picture. `ContentPresenter` draws it into its own
`CALayer` (`Sources/ToyStack/BrowserContentView.swift:9`). Nothing reacts when you press it:

- `ContentLayerView.hitTest` returns `nil` (`Sources/ToyStack/BrowserContentView.swift:54`), so the
  view never gets mouse events.
- The only left-button input is a `SpatialTapGesture` that sends a click to the page when you let go
  (`Sources/ToyStack/ToyStack.swift:68-76`). A press-and-drag is never seen.
- The engine only scrolls by a distance (`Frame.scrollBy(deltaY:)`, `Sources/Engine/Core/Frame.swift:1736`).
  The wheel and arrow keys use it. Nothing turns "thumb is at this height" into "page is at this scroll".

## How a real browser does it

1. **Mouse down** on the thumb: remember where inside the thumb you pressed (the *grab offset*).
   Do not send this press to the page.
2. **Mouse drag**: thumb top = pointer y − grab offset. Turn that into a scroll position:
   `scroll = thumbTop / thumbTravel × maxScroll`, where `thumbTravel = viewport height − thumb height`.
3. **Mouse up**: stop dragging, and do not send a click to the page.

Keeping the grab offset stops the page from jumping when you press the middle of the thumb.
Working from the absolute thumb position, not from how far the pointer moved since the last
event, means the thumb stays under the pointer. Small rounding errors do not add up, and
dragging past the top or bottom and coming back still lines up.

## Files that change

| File | Why |
|---|---|
| `Sources/Engine/Display/Scrollbar.swift` | The thumb math (height, travel, rect, grab area, thumb top → scroll) moves onto `ScrollbarGeometry`, so drawing and dragging share one formula |
| `Sources/Engine/Core/Frame.swift` | New `scrollTo(offset:)`; `scrollBy(deltaY:)` calls it |
| `Sources/Engine/Core/BrowserTab.swift` | Public `scrollTo(offset:)` that converts window pixels to page pixels (page zoom) |
| `Sources/Engine/Core/Browser.swift` | Stores the drag state: `beginScrollbarDrag`, `dragScrollbar`, `endScrollbarDrag`, `isDraggingScrollbar` |
| `Sources/ToyStack/ToyStack.swift` | One `NSEvent` monitor for left down/drag/up that feeds the three calls above |
| `profiling.md` | List the new `BrowserTab.scrollTo` span |
| `Tests/ToyStackTests/Display/ScrollbarGeometryTests.swift` (new) | Thumb math |
| `Tests/ToyStackTests/Core/ScrollbarDragTests.swift` (new) | Drag behavior through `Browser` |

### Design decision: where the drag state lives

- **Option A (recommended): `Browser`.** `Browser.activeSidebar` (`Sources/Engine/Core/Browser.swift:78`)
  already builds the thumb rect in window pixels from the *presented* scroll. That is the rect
  the user sees and presses. Drag state next to it uses the same numbers. Tests run without AppKit.
- **Option B: the AppKit view/monitor.** It keeps the engine unchanged, but the thumb math gets
  copied into the UI target, and you cannot test it without a window.

Trade-off: A adds four small members to an already large `Browser`. B is untestable and would duplicate the formula.

## Step 1: thumb math (Display)

Write the test first. It fails to compile because `thumbRect`, `thumbTravel`, `maxScroll`,
`thumbGrabContains`, and `scroll(forThumbTop:)` do not exist yet.

`Tests/ToyStackTests/Display/ScrollbarGeometryTests.swift` (new):

```swift
import CoreGraphics
import Testing

@testable import Engine

struct ScrollbarGeometryTests {
    private func geometry(docHeight: CGFloat, contentHeight: CGFloat = 600, scroll: CGFloat = 0) -> ScrollbarGeometry {
        return ScrollbarGeometry(docHeight: docHeight, contentHeight: contentHeight, contentWidth: 800, scroll: scroll)
    }

    @Test func aPageThatFitsHasNoThumbToGrab() {
        let bar: ScrollbarGeometry = geometry(docHeight: 600)

        #expect(bar.thumbRect == nil)
        #expect(!bar.thumbGrabContains(x: 795, y: 10))
    }

    @Test func thumbTopMapsBackToTheScrollThatPlacedIt() throws {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000, scroll: 900)
        let thumb: Rect = try #require(bar.thumbRect)

        #expect(abs(bar.scroll(forThumbTop: thumb.top) - 900) < 0.001)
    }

    @Test func thumbTopPastEitherEndClampsToTheScrollRange() {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000)

        #expect(bar.scroll(forThumbTop: -500) == 0)
        #expect(bar.scroll(forThumbTop: 0) == 0)
        #expect(bar.scroll(forThumbTop: bar.thumbTravel) == bar.maxScroll)
        #expect(bar.scroll(forThumbTop: 10_000) == bar.maxScroll)
    }

    @Test func pressBesideTheThinThumbStillGrabsIt() throws {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000)
        let thumb: Rect = try #require(bar.thumbRect)
        let midY: CGFloat = (thumb.top + thumb.bottom) / 2

        #expect(bar.thumbGrabContains(x: 799, y: midY))
        #expect(bar.thumbGrabContains(x: 789, y: midY))
        #expect(!bar.thumbGrabContains(x: 787, y: midY))
        #expect(!bar.thumbGrabContains(x: 795, y: thumb.bottom + 1))
    }

    @Test func viewportShorterThanTheMinimumThumbKeepsTheCurrentScroll() {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000, contentHeight: 20, scroll: 400)

        #expect(bar.thumbTravel < 0)
        #expect(bar.scroll(forThumbTop: 5) == 400)
    }
}
```

Then `Sources/Engine/Display/Scrollbar.swift`. The drawing does not change: `scrollbarBarRect` now reads the
same numbers from the geometry. The old literal `30` gets a name in `ScrollbarStyle`.

```diff
--- a/Sources/Engine/Display/Scrollbar.swift
+++ b/Sources/Engine/Display/Scrollbar.swift
@@ -5,6 +5,7 @@
     static let thumbWidth: CGFloat = 8
     static let thumbInset: CGFloat = 2
     static let thumbRadius: CGFloat = 4
+    static let thumbMinHeight: CGFloat = 30
     static let thumbColor: String = "#757575"
 }
 
@@ -13,20 +14,45 @@
     let contentHeight: CGFloat
     let contentWidth: CGFloat
     let scroll: CGFloat
+
+    var maxScroll: CGFloat { max(docHeight - contentHeight, 0) }
+
+    var thumbHeight: CGFloat {
+        return max((contentHeight / docHeight) * contentHeight, ScrollbarStyle.thumbMinHeight)
+    }
+
+    var thumbTravel: CGFloat { contentHeight - thumbHeight }
+
+    var thumbRect: Rect? {
+        guard maxScroll > 0 else { return nil }
+        let top: CGFloat = (scroll / maxScroll) * thumbTravel
+        return Rect(
+            left: contentWidth - ScrollbarStyle.thumbInset - ScrollbarStyle.thumbWidth,
+            top: top,
+            right: contentWidth - ScrollbarStyle.thumbInset,
+            bottom: top + thumbHeight
+        )
+    }
+
+    // The thumb is only 8 points wide, so a press anywhere in the strip from
+    // the window edge to the thumb's far side, at the thumb's height, grabs it.
+    func thumbGrabContains(x: CGFloat, y: CGFloat) -> Bool {
+        guard let thumb: Rect = thumbRect else { return false }
+        let gutterLeft: CGFloat = contentWidth - ScrollbarStyle.thumbWidth - 2 * ScrollbarStyle.thumbInset
+        return x >= gutterLeft && x <= contentWidth && y >= thumb.top && y < thumb.bottom
+    }
+
+    func scroll(forThumbTop top: CGFloat) -> CGFloat {
+        guard maxScroll > 0, thumbTravel > 0 else { return scroll }
+        let clamped: CGFloat = min(max(top, 0), thumbTravel)
+        return clamped / thumbTravel * maxScroll
+    }
 }
 
 func scrollbarBarRect(_ geometry: ScrollbarGeometry, forcedColors: Bool) -> DisplayOp? {
-    let maxScroll: CGFloat = max(geometry.docHeight - geometry.contentHeight, 0)
-    guard maxScroll > 0 else { return nil }
-    let barHeight: CGFloat = max((geometry.contentHeight / geometry.docHeight) * geometry.contentHeight, 30)
-    let barTop: CGFloat = (geometry.scroll / maxScroll) * (geometry.contentHeight - barHeight)
+    guard let thumb: Rect = geometry.thumbRect else { return nil }
     return .rrect(
-        rect: Rect(
-            left: geometry.contentWidth - ScrollbarStyle.thumbInset - ScrollbarStyle.thumbWidth,
-            top: barTop,
-            right: geometry.contentWidth - ScrollbarStyle.thumbInset,
-            bottom: barTop + barHeight
-        ),
+        rect: thumb,
         radii: .uniform(.px(ScrollbarStyle.thumbRadius)),
         color: BrowserColor(cssName: forcedColors ? ForcedColor.canvasText : ScrollbarStyle.thumbColor)
     )
```

Why the grab area is wider than the thumb: the thumb is 8 pt wide with a 2 pt gap on each side
(`ScrollbarStyle`). Hitting 8 pt exactly is hard. The grab strip runs from the window edge across
the full 12 pt. It sits on top of the page like the drawn thumb does, so a press there goes to
the scrollbar and not to the page.

Run: `swift test --filter ScrollbarGeometryTests` → 5 pass. Headless screenshots look the same because
`Frame.scrollbarCommands` (`Sources/Engine/Core/Frame.swift:1655`) uses the same function.

## Step 2: scroll to an absolute position (Core)

This is a pure refactor. The existing `ScrollRepaintPresentTests` cover `scrollBy`, and they must still pass.
Note that `Frame` already has `private func scrollTo(_ elt: DOMRef)` (`Sources/Engine/Core/Frame.swift:1595`).
The new method has a different argument label (`offset:`), so the two do not clash.

```diff
--- a/Sources/Engine/Core/Frame.swift
+++ b/Sources/Engine/Core/Frame.swift
@@ -1734,8 +1734,12 @@
     }
 
     func scrollBy(deltaY: CGFloat) {
+        scrollTo(offset: scroll - deltaY)
+    }
+
+    func scrollTo(offset: CGFloat) {
         state.runtime.animation.tween = nil
-        state.layout.scroll.offset = max(0, min(scroll - deltaY, maxScroll))
+        state.layout.scroll.offset = max(0, min(offset, maxScroll))
         if !checkInterestRegion() {
             browser?.applyScroll(scroll)
         }
```

```diff
--- a/Sources/Engine/Core/BrowserTab.swift
+++ b/Sources/Engine/Core/BrowserTab.swift
@@ -299,6 +299,12 @@
         }
     }
 
+    public func scrollTo(offset: CGFloat) {
+        browser?.measure.span("BrowserTab.scrollTo", category: .input) {
+            rootFrame.scrollTo(offset: offset / rootFrame.pageZoom)
+        }
+    }
+
     public func scrollElementDown() {
         focusedFrame.scrollElementDown()
     }
```

`profiling.md`, spans table (around line 394):

```diff
-| `BrowserTab.scrollAt`, `.scrollBy` | main | input dispatch |
+| `BrowserTab.scrollAt`, `.scrollBy`, `.scrollTo` | main | input dispatch |
```

Run: `swift test --filter ScrollRepaintPresentTests` → still passes.

## Step 3: drag state (Core)

Test first. It fails to compile because `beginScrollbarDrag`, `dragScrollbar`, `endScrollbarDrag`, and
`isDraggingScrollbar` do not exist. The failure-path cases:

- pressing the middle of the thumb must not move the page (the grab offset is kept);
- dragging far above the window stops at the top;
- a press on the page is not a drag, and later moves do nothing;
- moves after letting go do nothing;
- a lost mouse-up (for example, the app loses focus mid-drag) must not leave a drag running: the next
  press on the page starts fresh, and its moves do not scroll;
- at 200 % zoom, half the thumb travel lands at half of `maxScroll` in page pixels. I checked this test
  by removing the `/ pageZoom` in `BrowserTab.scrollTo`: it then fails with a 2918 px error.

`Tests/ToyStackTests/Core/ScrollbarDragTests.swift` (new):

```swift
import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ScrollbarDragTests {
    @Test func draggingTheThumbToTheBottomScrollsToTheEnd() async throws {
        let page: DragTestPage = try await DragTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.beginScrollbarDrag(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY + 600)
        page.browser.endScrollbarDrag()

        #expect(abs(page.frame.scroll - page.frame.maxScroll) < 0.5)
    }

    @Test func pressingInsideTheThumbDoesNotJumpThePage() async throws {
        let page: DragTestPage = try await DragTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.beginScrollbarDrag(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY)

        #expect(page.frame.scroll == 0)
    }

    @Test func draggingAboveTheTopClampsToTheStart() async throws {
        let page: DragTestPage = try await DragTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.beginScrollbarDrag(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY + 200)
        page.browser.dragScrollbar(y: -400)

        #expect(page.frame.scroll == 0)
    }

    @Test func pressOnThePageLeavesScrollToTheWheel() async throws {
        let page: DragTestPage = try await DragTestPage.open()
        defer { page.close() }

        #expect(!page.browser.beginScrollbarDrag(x: 400, y: 10))
        page.browser.dragScrollbar(y: 500)

        #expect(!page.browser.isDraggingScrollbar)
        #expect(page.frame.scroll == 0)
    }

    @Test func movesAfterReleaseDoNotScroll() async throws {
        let page: DragTestPage = try await DragTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.beginScrollbarDrag(x: thumb.midX, y: thumb.midY))
        page.browser.endScrollbarDrag()
        page.browser.dragScrollbar(y: thumb.midY + 300)

        #expect(page.frame.scroll == 0)
    }

    @Test func aLostReleaseDoesNotLetTheNextPagePressScroll() async throws {
        let page: DragTestPage = try await DragTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.beginScrollbarDrag(x: thumb.midX, y: thumb.midY))
        #expect(!page.browser.beginScrollbarDrag(x: 400, y: 10))
        page.browser.dragScrollbar(y: thumb.midY + 300)

        #expect(!page.browser.isDraggingScrollbar)
        #expect(page.frame.scroll == 0)
    }

    @Test func zoomedPageScrollsHalfwayWhenTheThumbMovesHalfItsTravel() async throws {
        let page: DragTestPage = try await DragTestPage.open()
        defer { page.close() }
        page.browser.setZoom(2)
        try #require(await page.settle())
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)
        let travel: CGFloat = page.browser.windowSize.height - thumb.height

        #expect(page.browser.beginScrollbarDrag(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY + travel / 2)

        #expect(abs(page.frame.scroll - page.frame.maxScroll / 2) < 0.5)
    }
}

@MainActor
private struct DragTestPage {
    let browser: Browser
    let frame: Frame
    let paths: [String]

    static func open() async throws -> DragTestPage {
        let id: String = UUID().uuidString
        let tracePath: String = NSTemporaryDirectory() + "scrollbar-drag-\(id).trace"
        let pagePath: String = NSTemporaryDirectory() + "scrollbar-drag-\(id).html"
        let html: String = #"<p>start</p><div style="height: 6000px;"></div><p>end</p>"#
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)

        let browser: Browser = Browser(tracePath: tracePath)
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()

        let tab: BrowserTab = try #require(browser.activeTab)
        let page: DragTestPage = DragTestPage(browser: browser, frame: tab.rootFrame, paths: [tracePath, pagePath])
        try #require(await page.settle(until: { tab.isLoaded && !tab.rootFrame.displayList.isEmpty }))
        return page
    }

    func settle(until condition: () -> Bool = { true }) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            browser.advanceFrame()
            if browser.isRenderIdle, condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return false
    }

    func close() {
        browser.stopAnimationTimer()
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
```

`DragTestPage` is a copy of the private `ScrollTestBrowser` in
`Tests/ToyStackTests/Core/ScrollRepaintPresentTests.swift:135`. Both tests are in `Core`, so the
`Support/` rule (helpers shared across *domains*) does not apply.

```diff
--- a/Sources/Engine/Core/Browser.swift
+++ b/Sources/Engine/Core/Browser.swift
@@ -30,6 +30,8 @@
     private var needsSpeakHoveredNode: Bool = false
     private var accessibilityFocusNode: AccessibilityNode? = nil
     private var liveRegionTexts: [NodeID: String] = [:]
+    private var scrollbarGrabOffset: CGFloat? = nil
+    public var isDraggingScrollbar: Bool { scrollbarGrabOffset != nil }
 
     private var activePresentation: TabPresentation {
         get { activeTab?.presentation ?? TabPresentation.empty }
@@ -75,23 +77,49 @@
         return BrowserColor(cssName: name).cgColor
     }
 
-    public var activeSidebar: (frame: CGRect, color: CGColor)? {
+    private var activeScrollbar: ScrollbarGeometry? {
         let contentHeight: CGFloat = windowSize.height
-        guard contentHeight > 0,
-            let bar = scrollbarBarRect(
-                ScrollbarGeometry(
-                    docHeight: activePresentation.scroll.maxScroll * pageZoom + contentHeight,
-                    contentHeight: contentHeight,
-                    contentWidth: windowSize.width,
-                    scroll: activePresentation.scroll.scroll * pageZoom
-                ),
-                forcedColors: activePresentation.preferences.usesForcedColors
-            ),
+        guard contentHeight > 0 else { return nil }
+        return ScrollbarGeometry(
+            docHeight: activePresentation.scroll.maxScroll * pageZoom + contentHeight,
+            contentHeight: contentHeight,
+            contentWidth: windowSize.width,
+            scroll: activePresentation.scroll.scroll * pageZoom
+        )
+    }
+
+    public var activeSidebar: (frame: CGRect, color: CGColor)? {
+        guard let geometry: ScrollbarGeometry = activeScrollbar,
+            let bar = scrollbarBarRect(geometry, forcedColors: activePresentation.preferences.usesForcedColors),
             case .rrect(let rect, _, let color) = bar
         else { return nil }
         return (rect.cgRect, color.cgColor)
     }
 
+    /// Returns false when the press missed the thumb, so the caller can hand
+    /// the press to the page as a normal click.
+    public func beginScrollbarDrag(x: CGFloat, y: CGFloat) -> Bool {
+        scrollbarGrabOffset = nil
+        guard let geometry: ScrollbarGeometry = activeScrollbar,
+            geometry.thumbGrabContains(x: x, y: y),
+            let thumb: Rect = geometry.thumbRect
+        else { return false }
+        scrollbarGrabOffset = y - thumb.top
+        return true
+    }
+
+    public func dragScrollbar(y: CGFloat) {
+        guard let grabOffset: CGFloat = scrollbarGrabOffset,
+            let geometry: ScrollbarGeometry = activeScrollbar,
+            let tab: BrowserTab = activeTab
+        else { return }
+        tab.scrollTo(offset: geometry.scroll(forThumbTop: y - grabOffset))
+    }
+
+    public func endScrollbarDrag() {
+        scrollbarGrabOffset = nil
+    }
+
     private var needsComposite: Bool = false
     private var needsRaster: Bool = false
     private var needsDraw: Bool = false
```

Run: `swift test --filter ScrollbarDragTests` → 7 pass.

Why `beginScrollbarDrag` clears the old offset first: AppKit can drop a mouse-up, for example when another
app takes focus in the middle of a drag. Without the reset, the next press on the page would pass through,
but its drag would still scroll the page, and its mouse-up would be swallowed, so the click would be lost.

## Step 4: wire the mouse (app)

```diff
--- a/Sources/ToyStack/ToyStack.swift
+++ b/Sources/ToyStack/ToyStack.swift
@@ -183,6 +183,30 @@
                 }
             )
             NSEvent.addLocalMonitorForEvents(
+                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
+                handler: { [weak app] event in
+                    guard event.window === browserWindow, let app else { return event }
+                    let type: NSEvent.EventType = event.type
+                    let location: NSPoint = event.locationInWindow
+                    let consumed: Bool = MainActor.assumeIsolated {
+                        let y: CGFloat = app.windowSize.height - location.y
+                        switch type {
+                        case .leftMouseDown:
+                            return y >= 0 && app.beginScrollbarDrag(x: location.x, y: y)
+                        case .leftMouseDragged:
+                            guard app.isDraggingScrollbar else { return false }
+                            app.dragScrollbar(y: y)
+                            return true
+                        default:
+                            guard app.isDraggingScrollbar else { return false }
+                            app.endScrollbarDrag()
+                            return true
+                        }
+                    }
+                    return consumed ? nil : event
+                }
+            )
+            NSEvent.addLocalMonitorForEvents(
                 matching: .otherMouseDown,
                 handler: { [weak app] event in
                     guard event.window === browserWindow else { return event }
```

Notes:

- The monitor must decide *right away* whether to swallow the press (`return nil`). It cannot do that
  inside the usual `Task { @MainActor in … }`, because that runs later. AppKit calls local monitors on the
  main thread, so `MainActor.assumeIsolated` is safe here and lets it call `Browser` directly.
- `MainActor.assumeIsolated` only returns values that are safe to share between threads (`Sendable`).
  `NSEvent` is not, so the closure returns a `Bool` ("did the scrollbar take this event?") and the
  `event` is returned outside it. `type` and `location` are read before entering, so `NSEvent` is never
  captured inside.
- Swallowing `leftMouseDown` and `leftMouseUp` while dragging stops `SpatialTapGesture` from also
  clicking the link or input under the thumb.
- Presses that miss the thumb return `event` unchanged, so page clicks work as before.
- `y = windowSize.height − locationInWindow.y` is the same conversion the wheel and hover monitors use.

## Verification

All four steps were tried in a throwaway copy of the repo (not your working tree):

- `swift build`: builds.
- `swift test --filter "ScrollbarGeometryTests|ScrollbarDragTests|ScrollRepaintPresentTests|ScrollTweenTests"`: 22 tests in 4 suites pass.
- Without the `scrollbarGrabOffset = nil` line, `aLostReleaseDoesNotLetTheNextPagePressScroll` fails.
- Not checked by hand in the running app: there is no tool on this machine to fake mouse input.
  To try it: `swift run ToyStack`, open a long page, press the grey bar on the right, and drag up and down.

## Not included

- Clicking the empty track above or below the thumb to jump a page.
- Dragging the scrollbar of an `overflow: scroll` box or an iframe. Those bars are drawn into the
  display list (`PaintSceneBuilder.iframeScrollbar`, `blockPaintScrollbar`), and only the wheel
  scrolls them (`Frame.scrollAt`).
