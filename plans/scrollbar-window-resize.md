# Resizing the window from the scrollbar edge scrolls the page

## What is wrong

Since the scrollbar can be pressed (`plans/scrollbar-drag.md`), grabbing the right edge of the
window to resize it moves the page instead:

- press on the empty part of the bar → the page jumps one page (track press),
- press where the thumb is → the thumb follows the mouse (thumb drag),
- in both cases the window does not resize.

## Why

macOS resizes a window from a thin strip around its frame. Part of that strip is *inside* the
window. Measured with synthetic mouse events on a 600 px wide window (macOS 24.6):

| press x (window points) | who gets it | window resizes |
|---|---|---|
| 592, 596 | the page view | no |
| 597 – 602 | `NSThemeFrame` (the window frame) | yes |

The page's scrollbar hit area is the last 12 px of the page (`ScrollbarGeometry.gutterContains`,
`Sources/Engine/Display/Scrollbar.swift:65-68`), 588 – 600. So 597 – 600 belong to both.

The left-mouse monitor (`Sources/ToyStack/ToyStack.swift:186-209`) runs *before* the window
handles the press. It called `Browser.pressScrollbar` for every press in the bar, and returned
`nil` (swallow) when it hit. The window never saw the mouse-down, so it never started resizing;
the page scrolled instead.

## Fix

Ask AppKit who owns the press before treating it as a scrollbar press. The window's frame view
(`contentView.superview`) answers `hitTest` with itself on the resize strip and with a view inside
the content otherwise. That is the same decision `NSWindow.sendEvent` would make without the
monitor, so it stays right in full screen (no strip) and for windows that cannot resize, with no
hard-coded strip width.

### Files

| File | Why |
|---|---|
| `Sources/Engine/Platform/NSWindow+ContentPress.swift` (new) | `contentReceivesPress(at:)`: does this press go to the page or to the window frame? |
| `Sources/ToyStack/ToyStack.swift` | the mouse-down monitor only presses the scrollbar when the page owns the press |
| `Tests/ToyStackTests/Platform/WindowEdgePressTests.swift` (new) | resize edge, corner, inside the bar, fixed-size window, outside the window |

### `Sources/ToyStack/ToyStack.swift`

```diff
                 handler: { [weak app] event in
-                    guard event.window === browserWindow, let app else { return event }
+                    guard let window: NSWindow = event.window, window === browserWindow, let app else { return event }
                     let type: NSEvent.EventType = event.type
                     let location: NSPoint = event.locationInWindow
                     let consumed: Bool = MainActor.assumeIsolated {
                         let y: CGFloat = app.windowSize.height - location.y
                         switch type {
                         case .leftMouseDown:
-                            return  y >= 0 && app.pressScrollbar(x: location.x, y: y)
+                            return y >= 0 && window.contentReceivesPress(at: location) && app.pressScrollbar(x: location.x, y: y)
```

Drag and up need no change: when the window resizes, its own tracking loop takes those events,
and `scrollbarPress` was never set.

## Verification

- `swift test --filter "WindowEdgePressTests|ScrollbarTrackTests|ScrollbarDragTests|ScrollbarGeometryTests"`: 24 tests pass.
- Real app, synthetic drag from 1 px inside the right edge, 40 px left, at 25% (thumb) and 80% (track) height:
  - before: width 1360 → 1360 both times (page scrolled instead),
  - after: width 1440 → 1400 → 1360.
