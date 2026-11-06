# Resize leaves the final width unlaid out

Status: **applied** (2026-11-06).

## Symptom

Resize the window down and release the pointer. The window keeps showing the
previous layout fitted into the new viewport (smaller, denser text). Text size
and line breaks do not change at the new width. Moving the pointer over the page
makes the new layout appear immediately.

First seen after `534410b` (`perf: reflow during resize instead of waiting for
the pointer`).

Evidence: `Screen Recording 2026-11-06 at 16.31.19.mov`. The page stays
pixel-identical from 9.0 s to 11.75 s; the first changed frame is 12.0 s, right
after the pointer moves.

## Root cause

The async layout result is discarded correctly, but the frame clock is asked for
an animation frame instead of a render pass, and the render request that the
last resize produced has already been consumed.

`Sources/Engine/Core/Frame.swift:1288`:

```swift
layoutInFlight = false
if let key: LayoutJobKey = layoutJobKey,
    key.isStale(currentWidth: frameWidth, currentZoom: pageZoom)
{
    layoutJobKey = nil
    layoutInFlightDirty = false
    state.layout.tree.isDirty = true
    requestAnimationFrame()          // <-- only wakes the clock
    return
}
```

The frame clock is not enough, because `render()` is gated on a different flag
(`Sources/Engine/Core/Frame.swift:1209`):

```swift
if state.runtime.schedule.needsRender {
    state.runtime.schedule.needsRender = false
    render()                         // layout is started here
```

`requestAnimationFrame()` only sets `Browser.needsAnimationFrame`
(`Frame.swift:207`). `needsRender` is never set again, so the tick that
`finishAsyncLayout` requested does nothing: no render, no new `startAsyncLayout`.

### The race, step by step

1. Drag starts. A tick starts a background layout for width `W1`.
2. The pointer moves again to `W2`. `setNeedsViewportResize` sets
   `needsRender = true` and marks `layoutInFlightDirty`.
3. The next tick consumes `needsRender` in `Frame.runAnimationFrame`
   (`Frame.swift:1209`), calls `render()`, and `render()` returns early because
   `layoutInFlight` is true (`Frame.swift:931`). The request is now gone.
4. The `W1` job finishes. `isStale(W2)` is true, so the result is thrown away.
   Only `isDirty` is set and `requestAnimationFrame()` is called.
5. The pointer stops. The next tick sees `needsRender == false`, so no layout
   ever starts for `W2`.
6. The presenter keeps showing the last committed content, previewed from its
   base view size (`ContentPresenter` + `ContentPresentationState`), which is
   why the text looks fitted instead of reflowed.
7. Any later input that sets `needsRender` revives the tree. A mouse move does
   this through `BrowserTab.hover` -> `setNeedsHoverCheck`
   (`Frame.swift:2039`), which is exactly "move the pointer and the text fixes
   itself".

### Why `534410b`

Before it, async mode presented a preview and returned for the whole 120 ms
preview window. The first layout after a drag started *after* the pointer
stopped, at the final width, so the stale path was rare. `534410b` lets the
frame clock lay out during the preview, so a drag routinely leaves a job in
flight for an intermediate width. Releasing the pointer in that window is what
triggers the stale discard with no remaining render request.

## Fix

Replace the animation-frame request with the normal layout request. It marks the
tree dirty, sets `needsRender`, and wakes the clock in one call
(`Sources/Engine/Core/Frame.swift:2010`).

```diff
--- a/Sources/Engine/Core/Frame.swift
+++ b/Sources/Engine/Core/Frame.swift
@@ -1291,8 +1291,7 @@
         {
             layoutJobKey = nil
             layoutInFlightDirty = false
-            state.layout.tree.isDirty = true
-            requestAnimationFrame()
+            setNeedsLayout()
             return
         }
```

Only a full pass is valid here: the result was produced for another viewport
width, so `forced = true` from `setNeedsLayout()` is correct, and the field
dirty flags from the resize are still set.

### Alternatives

| Option | Change | Trade-off |
|---|---|---|
| **A (recommended)** | `setNeedsLayout()` in the stale branch | One call, matches every other invalidation path, sets the flag the clock actually reads. |
| B | Keep `isDirty = true`, add `state.runtime.schedule.needsRender = true` next to `requestAnimationFrame()` | Same effect today, but leaves two flags to remember and does not force the pass. The paint-only cleanup in `render()` (`Frame.swift:925`) could clear `isDirty` when no field is dirty. |
| C | Make the clock render when `isDirty` even if `needsRender` is false | Hides the missing request and turns any stray dirty tree into a render pass. |

## Test first

New file `Tests/ToyStackTests/AsyncResizeRestartTests.swift`. The background
suite convention applies: it records into the process-wide profiler, so keep it
in the opt-in suite like `BackgroundLayoutTests`.

```swift
import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct AsyncResizeRestartTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func frameClockRestartsLayoutAfterAStaleResult() async throws {
        let html: String = (0..<40).map { index in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; }"
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        // The page loaded and painted before the resize.
        page.frame.clearPaintRequest()

        // A layout for 400 starts.
        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        let started: Bool = page.frame.isLayoutInFlight
        #expect(started)

        // Resize while it runs; this tick consumes the render request.
        page.tab.resize(width: 300, height: 600)
        page.frame.runAnimationFrame()
        let stillRunning: Bool = page.frame.isLayoutInFlight
        #expect(stillRunning)

        // The 400 result is discarded as stale. Nothing else invalidates.
        let deadline: Date = Date().addingTimeInterval(5)
        while page.frame.isLayoutInFlight, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        page.frame.clearPaintRequest()

        // The frame clock alone must start the pass for the latest width.
        page.frame.runAnimationFrame()
        let restarted: Bool = page.frame.isLayoutInFlight
        let asyncOn: Bool = browser.usesAsyncLayout   // also keeps the weak tab.browser alive
        #expect(asyncOn)
        #expect(restarted, "the final width never restarted after the stale discard")
    }
}
```

Two traps found while reproducing:

- `BrowserTab.browser` is `weak`. If the test only keeps `page`, the browser is
  released and `render()` silently takes the synchronous path; `isLayoutInFlight`
  stays false and the test fails for the wrong reason.
- Do not put `page.frame.isLayoutInFlight` inside `#expect` directly. When the
  expectation fails, Swift Testing reflects the captured page graph and the
  failure message hangs. Copy the value into a `Bool` first.

Failing for the intended reason before the fix: `restarted` is `false`.
Passing after: `restarted` is `true`, and a follow-up pass installs the tree at
width 300.

## Verification

Reproduced, fixed, and applied on 2026-11-06:

| Run | Result |
|---|---|
| `AsyncResizeRestartTests` before fix | `started`, `stillRunning` pass; `restarted` fails |
| `AsyncResizeRestartTests` with the fix | passes |
| Control (no resize while the job runs) | final width installs at 300, before and after |
| Hover control | `setNeedsHoverCheck()` + tick restarts the pass, before and after |
| `TOYSTACK_BACKGROUND_LAYOUT_TEST=1 swift test` | 3 tests in the two background suites pass |
| Full default suite with the fix | 281 tests / 50 suites pass |

After applying, also confirm in a GUI trace (`browser.trace`): release the
pointer mid-drag and check that a paint/raster generation follows within one
frame budget without any pointer movement. The `BrowserTab.resize` event that
ends a drag must be followed by a `view.presentation` with `preview: 0` for the
final width, not by an idle `BrowserTab.animFrame` gap.

## Related

`plans/issues/resize-flow-roadmap.md` — recorded as the Step 4 follow-up.
