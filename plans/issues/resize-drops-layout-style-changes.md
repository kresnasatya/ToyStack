# Resize drops the style changes that the next layout needs

Status: **applied** (2026-11-07).
Files: `Sources/Engine/Style/StyleFields.swift`, `Sources/Engine/Core/Frame.swift`,
`Tests/ToyStackTests/AsyncResizeStyleChangeTests.swift`.
Evidence: `browser.trace-lg`, `browser.trace-sm`, `Screen Recording 2026-11-07 at 08.39.35.mov`.

## Symptom

Crossing the `max-width: 800px` breakpoint while resizing does not change the
text size, in both directions:

- large window -> shrink below 800: text keeps the 24 px glyphs (reflowed
  lines, old font)
- small window -> grow above 800: text keeps the 18 px glyphs

The style tree is correct. Every breakpoint pass reports
`style.font-size.changed.*` for all 368 nodes. The layout tree keeps the old
font because the pass that would apply it is discarded.

This is different from `resize-leaves-stale-font-size.md` (the percentage
one-ULP bug, fixed in `e799a0d`). That fix removed the accidental second
layout that used to repair this case, so now the stale font stays visible.

## Trace evidence

In both traces every media flip is followed by another resize event inside the
same frame:

| Trace | Frame | Flip width | Style pass ends | Next resize |
|---|---|---|---|---|
| lg | 62 | 780 -> 18 px | 1794012076534134 | 759 at 1794012076534865 |
| lg | 130 | 828 -> 24 px | 1794012081551213 | 873 at 1794012081552077 |
| lg | 218 | 782 -> 18 px | 1794012087567948 | 807(?) same frame |
| sm | 65 | 820 -> 18 px | 1794012109646047 | 859 at 1794012109650314 |
| sm | 173 | 800 -> 18 px | 1794012114563448 | 798 at 1794012114567281 |
| sm | 268 | 807 -> 24 px | 1794012120246290 | 842 at 1794012120250728 |

Each pass reports `style.applied=368`, `style.apply.force=367`,
`style.changed.font-size=1` (html only) and 368
`style.font-size.changed.<tag>` counters. So the computed font sizes did move:
`html` 24 <-> 18 and every forced descendant re-inherited it.

After the drag stops the paints re-emit every line
(`paint.cache.store.lines.count` 54-59) and the document reflows, so the
display list is new. The reflow just measures the old font.

## Reproduction (verified)

Temporary test, same shape as the GUI event order:

1. Load at 900, settle a background pass.
2. Resize to 700 (crosses the breakpoint); `render()` applies 18 px and starts
   the post-flip background job.
3. Resize to 650 before that job finishes.
4. Drive the frame clock until settled.

Result (before the fix):

```text
docWidth 624.0          # a pass did run for the new width
boxSizes [24.0]         # every line box still measures and paints 24 px
ownerSizes [18.0]       # every element's computed font-size is 18 px
```

Control without step 3 (`settledFlipRefreshesTheFont`) gives
`boxSizes [18.0] ownerSizes [18.0]`.

## Root cause

`LayoutInputsBuilder.build` empties the DOM's pending layout-change set while
it builds the background job:

- `Sources/Engine/Style/StyleFields.swift:19-26` — `takeLayoutChanges()`
  removes the changes.
- `Sources/Engine/Layouts/LayoutInputsBuilder.swift:48` — every node is asked
  once while the inputs are built.
- `Sources/Engine/Core/Frame.swift:1267` — `startAsyncLayout` builds those
  inputs on the main thread before launching the job.

The changes are now owned by that job's `LayoutInputs.styleChanges`
(`Sources/Engine/Layouts/LayoutInputs.swift:13,54`). If the viewport moves on
while the job runs, `finishAsyncLayout` (`Sources/Engine/Core/Frame.swift:1311-1318`)
throws the completed tree away. The changes went with it.

The next job builds inputs with an empty change set, so
`LayoutTree.consumeStyleChanges()` marks no dependents. The block's
`.inlineContent` is never dirtied, even though `font-size` is one of its
declared inputs (`BlockLayoutPass.swift:63-87`). Because only the width
changed, the inline path takes the reuse branch
(`Sources/Engine/Layouts/BlockLayoutPass.swift:388-440`):

```swift
let inlineContentChanged = isDirty(.inlineContent, at: id) || ...
if inlineContentChanged { refreshInlineItems(...) }
let canReusePlan = !inlineContentChanged || preservedItems   // == true
if shouldPlace {
    placeInlineItems(id, plan: plan, oldPlan: oldPlan, refreshMetrics: preservedItems)
}
```

- `refreshInlineItems` is skipped, so `inlineItems` keep the 24 px font and the
  old measured widths. The new line plan is computed from those stale widths.
- `refreshMetrics` is false, so `placeInlineItems` reuses old line boxes and
  builds new ones with `item.run.font` — still 24 px.

That is exactly the recording: line breaks follow the new width, glyph size
does not. A brand-new load at the same width is correct because the full
cascade records every `font-size` change for the first layout.

## Fix

### Option A (recommended): give the changes back when a job is discarded

Keep the job's change snapshot on the frame; on the stale branch, merge it back
into each node's `StyleFields` before asking for the next pass.

Precise, local, and keeps the dependency model. Only the discarded job's own
changes are restored; a style pass that ran while the job was in flight leaves
its newer changes untouched.

`Sources/Engine/Style/StyleFields.swift`

```diff
     func takeLayoutChanges() -> Set<StyleProperty> {
         guard !layoutChanges.isEmpty else { return [] }
         let changes: Set<StyleProperty> = layoutChanges
         layoutChanges.removeAll(keepingCapacity: true)
         return changes
     }
 
+    /// Puts back the changes a background layout took before being discarded.
+    /// A job that never installs must not consume what the next pass needs to
+    /// know: without the change set, a width-only pass recomputes lines from
+    /// the old inline items and keeps their old fonts.
+    func requeueLayoutChanges(_ changes: Set<StyleProperty>) {
+        guard !changes.isEmpty else { return }
+        layoutChanges.formUnion(changes)
+    }
```

`Sources/Engine/Core/Frame.swift`

```diff
     private var layoutJobID: UInt = 0
     private var layoutJobKey: LayoutJobKey?
+    /// Style changes the in-flight job consumed when it started. Restored if
+    /// the viewport moves on and the completed tree is dropped.
+    private var layoutJobStyleChanges: [NodeID: Set<StyleProperty>] = [:]
     private var layoutJobSize: CGSize = .zero
```

```diff
         let inputs: LayoutInputs = LayoutInputsBuilder.build(dom: dom)
+        layoutJobStyleChanges = inputs.styleChanges
         let box: LayoutBox
```

```diff
             layoutJobKey = nil
             layoutInFlightDirty = false
+            requeueLayoutJobStyleChanges()
             setNeedsLayout()
             return
         }
         layoutJobKey = nil
+        layoutJobStyleChanges.removeAll(keepingCapacity: true)
         guard let box: LayoutBox = state.layout.tree.box, box.tree.dom === dom else {
```

```diff
+    /// A discarded job already took its style changes out of the DOM. Put them
+    /// back so the next job marks `.font` / `.inlineContent` and refreshes the
+    /// inline items instead of reusing the previous font.
+    private func requeueLayoutJobStyleChanges() {
+        guard !layoutJobStyleChanges.isEmpty else { return }
+        for (id, changes) in layoutJobStyleChanges {
+            guard dom.node(id) != nil else { continue }
+            dom.ref(id).style.requeueLayoutChanges(changes)
+        }
+        layoutJobStyleChanges.removeAll(keepingCapacity: true)
+    }
```

The sync path does not need this: it builds inputs and lays out before it can
be invalidated. The first-tree path (`LayoutTree.init(dom:)`) also passes its
inputs straight into the new tree.

### Option B: mark all inline content dirty on a stale discard

`Source`-local, but coarse: it re-measures every block even when nothing
changed, and it does not restore other layout-affecting style changes
(`display`, `position`, `white-space`, ...). Use only as a stopgap.

## Test first

New opt-in suite `Tests/ToyStackTests/AsyncResizeStyleChangeTests.swift`
(the background suites already use `TOYSTACK_BACKGROUND_LAYOUT_TEST=1`):

```swift
import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct AsyncResizeStyleChangeTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func staleJobKeepsTheFontFlipPending() async throws {
        let paragraph: String = String(
            repeating: "alpha beta gamma delta epsilon zeta eta theta ",
            count: 20
        )
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p id=\"p\">\(paragraph)</p>",
            rules: """
                html { width: 600px; font-size: 24px; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                body { display: block; }
                p { display: block; }
                """
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        func settle() async throws {
            let deadline: Date = Date().addingTimeInterval(5)
            while page.frame.isLayoutInFlight, Date() < deadline {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
        }

        page.tab.resize(width: 900, height: page.frame.frameHeight)
        page.frame.render()
        try await settle()

        // The flip pass starts a job for 700; the next resize makes it stale.
        page.tab.resize(width: 700, height: page.frame.frameHeight)
        page.frame.render()
        page.tab.resize(width: 650, height: page.frame.frameHeight)

        for _ in 0..<6 {
            page.frame.runAnimationFrame()
            try await settle()
        }

        let doc: LayoutTree = try #require(page.frame.document)
        var boxSizes: Set<CGFloat> = []
        var ownerSizes: Set<CGFloat> = []
        for line in treeToList(doc, doc.rootID) where doc.isLine(line) {
            guard let boxes: [InlineBox] = doc.currentInlineBoxes(line) else { continue }
            for box in boxes {
                boxSizes.insert(box.text.font.size)
                ownerSizes.insert(
                    DOMRef(id: box.dom, dom: doc.dom)
                        .inheritedStyleOwner.style.computed.text.font.size
                )
            }
        }
        #expect(doc.width(doc.rootID) < 650, "the pass for the new width did not run")
        #expect(boxSizes == ownerSizes, "line boxes kept the old font after a stale job")
    }
}
```

Before the fix: `boxSizes == [24.0]`, `ownerSizes == [18.0]`, `docWidth == 624`
(a pass ran, the font did not refresh). After the fix both sets are `[18.0]`.

Keep the sync controls (`StyleInheritanceTests.growingBackAcrossTheBreakpointRefreshesLineBoxFonts`)
and the async settle control (`BackgroundLayoutTests.asyncBreakpointFlipRefreshesLineBoxFonts`)
as they are.

## Verification

| Check | Expected |
|---|---|
| New test before fix | fails with `24.0` vs `18.0` |
| New test after fix | passes |
| `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test` | all background tests pass |
| `swift test` | existing suite unchanged |
| GUI, large -> small | text switches to 18 px when the drag stops, no hover |
| GUI, small -> large | text switches to 24 px when the drag stops, no hover |
| GUI trace | after a flip pass, the discarded resize is followed by a pass whose lines are stored with the new font (check `paint.cache.store.lines.count` and the screenshot, not the font counters) |

## What is not the cause

- The cascade: 368/368 font-size changes are reported at every flip.
- Paint caches: they re-emit every line after the drag; the display list is new,
  the glyphs are old.
- The presenter: the generation completes (`deferred=0`); this renders the
  stale display list correctly.
- `refreshReusedLine` for value lines: the reuse eligibility check is fine; the
  items handed to it are already stale because the change set was lost.

## Applied result (2026-11-07)

- `StyleFields.requeueLayoutChanges`: merges a discarded job's change set back
  into the DOM.
- `Frame` keeps `layoutJobStyleChanges` from `startAsyncLayout`; the stale
  branch in `finishAsyncLayout` calls `requeueLayoutJobStyleChanges()` before
  `setNeedsLayout()`. An accepted install clears the snapshot.
- Regression: `AsyncResizeStyleChangeTests.staleBackgroundJobStillAppliesTheFontFlip`
  failed before with `boxSizes [24.0]` vs `ownerSizes [18.0]` (doc width 624),
  and passes after with both sets `[18.0]`.
- `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test`: 288 tests / 53 suites pass.
- `swift test`: 288 tests / 53 suites pass; the opt-in suite is skipped.
- Live app run (`TOYSTACK_STYLE_LOG=1`): the drag across 800 logs a viewport
  pass at width 780 (`flipped=1`, `applied=368`). Screen capture of the window
  was blocked by the host's Screen Recording permission, so the visual proof
  comes from the line-box assertion above rather than a video frame.

