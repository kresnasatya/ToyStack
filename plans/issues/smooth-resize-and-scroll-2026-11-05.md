# Smooth Scroll and Smooth Resize: Responsibility, Comparison, and ToyStack Plan

Status: analysis + proposed plan. No code is changed by this document.

## Short answer

- A rendering engine owns **scroll semantics** and **resize layout semantics**, not the window animation itself.
- Smooth scroll is usually split: the engine decides what is scrollable and which layer moves; the compositor/OS moves it. The engine only pays per-scroll repaint when a page cannot be composited.
- Smooth resize is also split: the OS animates the window; the engine must coalesce resize events, reflow at the latest size, and keep a complete frame visible. A slow reflow must not be allowed to present a stale size.
- ToyStack already has the right two ideas: tile sublayers for scroll, and a resize preview that postpones layout. The gaps are (a) the preview distorts content, (b) preview scheduling is timer-based instead of frame-based, and (c) a width reflow is still 90-153 ms on the traced page, so the snap after a drag is unavoidable until layout gets cheaper.

## 1. What is a rendering engine?

A browser is more than its engine:

| Part | Job |
|---|---|
| Browser UI / chrome | tabs, address bar, window, input routing |
| Rendering engine | HTML/CSS/JS integration, DOM, style, layout, paint, compositing hand-off |
| Script engine | JavaScript execution (JSC/V8/SpiderMonkey) |
| Networking / storage | fetch, cache, cookies, origins |
| OS compositor / display | window animation, final composition, display timing |

The rendering engine is the part that answers: **given this document, this viewport, and this time, what pixels should appear, and which parts must be recomputed?**

```mermaid
flowchart LR
  A[bytes] --> B[DOM]
  B --> C[style / cascade]
  C --> D[layout / reflow]
  D --> E[paint / display list]
  E --> F[composite / layers]
  F --> G[raster / tiles]
  G --> H[present]
```

"Rendering" in browser terminology is the whole resolution above, not only the final draw:

- Parsing and DOM building are not rendering yet.
- Style, layout, paint, compositing, raster are rendering.
- A scroll that moves an existing layer is rendering without style/layout/paint.
- A resize that changes layout is rendering with a mandatory reflow.

That distinction matters for the question: **scroll and resize are viewport operations that force different amounts of rendering work.**

## 2. Who owns scroll and resize?

| Concern | Rendering engine | Compositor / OS |
|---|---|---|
| What is scrollable, scrollport, overflow, clamping | yes | no |
| Nested scrollers, hit-testing, fixed/sticky | yes | consumes the layer tree |
| Scroll offset semantics, `scroll` events, anchoring | yes | no |
| Moving pixels during a scroll | only when not composited | yes, usually on its own thread |
| Window drag/resize animation | no | yes |
| Reflow for a new viewport | yes | no |
| Keeping the last complete frame visible during resize | policy + frame supply | yes, presents/clips it |
| Coalescing stale resize sizes | yes | reports sizes |

So:

- **Smooth scroll is a shared responsibility.** The engine's job is to make the scroll *compositable* and correct. If the page contains a blend fallback or a scroll-dependent effect, the engine must repaint per scroll and smoothness becomes its problem.
- **Smooth resize is mostly the engine's layout problem plus the compositor's presentation problem.** The engine cannot make the OS window resize smoother, but it can avoid reflowing every intermediate size, avoid presenting mismatched frames, and make the final reflow fast enough to hide.

## 3. How real engines do it

| Engine | Scroll motion | Resize behavior | Key mechanism |
|---|---|---|---|
| Blink / Chromium | `cc` compositor thread receives input and animates scroll offsets | Browser UI sends the new size; renderer coalesces at `BeginMainFrame`; display compositor (`viz`) clips/pads the last frame instead of showing stale gutters | `cc/input` handles scrolling on the compositor thread; `viz` clips the viewport to the frame it actually has; reflow stays on the main thread |
| WebKit | `ScrollingCoordinator` / `ScrollingTree`; async scrolling thread when possible | `FrameView` resize triggers layout on the main thread; scrolling keeps running on the scrolling thread while the main thread reflows | fixed/sticky and scroll offsets live in the scrolling tree; main thread remains the layout owner |
| Gecko | APZ (Async Pan/Zoom) on the compositor thread; main thread receives displayport updates | `PresShell` resize reflow on the main thread, driven by the refresh driver; retained display lists limit repaint | two copies of scroll state: main-thread layout copy + compositor APZ copy |
| Servo | WebRender compositor; style/layout are the differentiator, with parallel style and layout work | Reflow on the layout pipeline; WebRender composites the result | parallelism reduces reflow latency; it does not remove the need to reflow for a new viewport |
| LadyBird | Async scrolling on an out-of-process compositor since May 2026 | Layout still runs in the WebContent process; compositor keeps scrolling while the main thread is busy | the most recent engine to adopt the same split as Blink/WebKit/Gecko |
| ToyStack | Main thread only; CALayer sublayers + content offset | 120 ms preview latch, then one full reflow on main | correct idea, but preview and reflow are still coupled to the main thread |

The common pattern is not "the engine draws every scroll frame". It is:

1. Put scroll motion on a thread/process that is not blocked by layout.
2. Coalesce resize to the latest size per frame.
3. Keep the last complete frame on screen while the new one is being built.
4. Never present a frame whose size does not match the window.
5. Reflow only at the latest size, not for every intermediate event.
6. Make reflow fast enough that preview is the exception, not the normal path.

LadyBird's May 2026 note is a good confirmation: before async scrolling, "a busy page could make scrolling stutter"; after moving scrolling to the compositor, "scrolling stays smooth even while the main thread is busy with layout or JavaScript." ToyStack is currently in LadyBird's "before" state.

## 4. ToyStack today

### 4.1 Resize path

```mermaid
sequenceDiagram
    participant S as SwiftUI
    participant B as Browser
    participant T as BrowserTab
    participant F as Frame
    participant P as Present thread

    S->>B: onGeometryChange(newSize) ToyStack.swift:244
    B->>T: resize(width, height) Browser.swift:149
    T->>F: setViewport + setNeedsViewportResize BrowserTab.swift:250
    F->>F: mark width/zoom dirty Frame.swift:1902
    alt estimated frame > 33 ms
        B->>B: beginResizePreview, 120 ms timer Browser.swift:161
        B->>P: dispatchPresent(old content, new size)
        Note over B: animationTick returns while preview Browser.swift:227
    else fast enough
        B->>F: render on next tick
    end
    B->>F: after 120 ms idle, render at latest size
    F->>F: style? -> layout -> paint
    F->>P: commit + present
```

Relevant code:

- `Sources/ToyStack/ToyStack.swift:244` — every geometry change calls `app.resize(to:deferLayout: true)`.
- `Sources/Engine/Core/Browser.swift:146` — updates every tab, then decides preview vs live layout from `estimatedFrameTime`.
- `Sources/Engine/Core/Browser.swift:161` — `beginResizePreview` restarts a 120 ms `DispatchWorkItem` and presents old content.
- `Sources/Engine/Core/Browser.swift:222` — `animationTick` drops the frame while `isResizePreview`.
- `Sources/Engine/Core/BrowserTab.swift:238` — records `widthChanged` / `heightChanged`; calls `setViewport` and `setNeedsViewportResize`.
- `Sources/Engine/Core/Frame.swift:74` — width change marks the document width dirty; height alone does not.
- `Sources/Engine/Core/Frame.swift:1902` — `setNeedsViewportResize` marks width+zoom dirty and either restyles or forces layout.
- `Sources/Engine/Core/Frame.swift:781` — render does style, layout, paint.
- `Sources/ToyStack/ContentPresenter.swift:181` — preview scales the old content by `newSize / previousSize`; this is why text stretches during a drag.

What is already right:

- Height-only resize does no block work and clamps scroll; this is covered by `Tests/ToyStackTests/ViewportResizeTests.swift:10`.
- Width-only resize reuses line/text objects and skips unchanged fixed-width subtrees in the tested cases.
- Preview is only entered when the frame estimate is over two frame budgets; fast pages reflow live.
- Raster and present already run off the main thread.

What is still wrong:

- The preview is a non-uniform scale: text is stretched, not resized.
- The debounce is a main-queue timer, not the frame clock. It can fire late behind queued resize events/presents, and it cannot be tested as a pure policy.
- Presents during a drag are per event, not per frame.
- The final width reflow is 90-153 ms on the traced page, so the drag always ends with a visible snap after 125-174 ms of debounce plus the reflow.
- Wheel scrolling is handled on the main thread. A 100 ms reflow blocks it; there is no compositor-owned scroll state.

### 4.2 Scroll path

```mermaid
sequenceDiagram
    participant E as NSEvent
    participant T as BrowserTab
    participant F as Frame
    participant B as Browser
    participant R as RasterScheduler
    participant P as Present thread

    E->>T: scrollAt(x, y, deltaY) ToyStack.swift:189
    T->>F: scrollAt -> scrollBy Frame.swift:1409
    F->>B: applyScroll(scroll) Browser.swift:664
    B->>P: dispatchPresent every event
    B->>R: re-plan only when scroll crosses a 128 px tile
    R-->>P: new tile images
    Note over B: no reflow while scrolling
```

Relevant code:

- `Sources/ToyStack/ToyStack.swift:175` — wheel monitor; precise deltas are passed through.
- `Sources/Engine/Core/Frame.swift:1409` — nested iframe and scroll-block hit-testing first, then document scroll.
- `Sources/Engine/Core/Frame.swift:1458` — direct offset update; no tween for wheel.
- `Sources/Engine/Core/Frame.swift:1390` — keyboard scroll uses a 12-frame `ScrollTween`.
- `Sources/Engine/Core/Browser.swift:664` — updates the presented scroll offset, presents, and only re-rasters when the tile step is crossed.
- `Sources/ToyStack/ContentPresenter.swift` — presents on its own queue; sublayer update is ~0.1 ms median.

This is a compositor-style scroll for pages that use tile sublayers. The weakness is ownership of input: the main thread must be free to consume the wheel event.

## 5. What `browser.trace` says

This is a GUI trace: it contains `browser.present`, `view.apply`, `view.commit`, and `coalesced`. It is not a headless trace.

Span: 29.46 s, 200 frame ids, 10,699 events.

### 5.1 Resize

307 resize events in 11 bursts, 16.7 ms apart within a burst.

| Burst | Events | Burst span | Reflow starts after last event | Layout duration |
|---|---:|---:|---:|---:|
| 1 | 32 | 528 ms | 125 ms | 96 ms |
| 2 | 27 | 445 ms | 161 ms | 143 ms |
| 3 | 43 | 711 ms | 129 ms | 100 ms |
| 4 | 35 | 611 ms | 166 ms | 153 ms |
| 5 | 29 | 518 ms | 138 ms | 93 ms |
| 6 | 10 | 163 ms | 127 ms | 87 ms |
| 7 | 36 | 594 ms | 170 ms | 148 ms |
| 8 | 22 | 361 ms | 161 ms | 146 ms |
| 9 | 21 | 345 ms | 134 ms | 101 ms |
| 10 | 20 | 383 ms | 174 ms | 151 ms |
| 11 | 18 | 296 ms | 172 ms | 149 ms |

So the user-visible sequence is: smooth preview during the drag, then **163-327 ms** before the reflowed content replaces it.

Per-stage cost on resize frames:

| Stage | Time | Notes |
|---|---:|---|
| `BrowserTab.layout` | 38-153 ms | 15 passes; median 101 ms |
| `layout.visit` | 20-85 ms | all 1,773 nodes rebuilt on every width change |
| `layout.inline.place` | 35-56 ms | line construction; 640-2,023 lines |
| `layout.inline.place.lineChildren` | 12-27 ms | children + dependency edges |
| `layout.line.place` | 2-15 ms | per-line child placement |
| `layout.inline.place.items` | 37 ms on breakpoint flips | item refresh |
| `layout.inputs.build` | 12-15 ms | rebuilt on some passes, reused on others |
| `BrowserTab.style` | 30-34 ms on breakpoint flips; 1-5 ms otherwise | only 6 of 15 resize frames style at all |
| `BrowserTab.paint` | 5.8-8.7 ms | full display-list rebuild |
| `raster.plan` | ~1 ms | not the bottleneck |
| `raster.strip` | 2-9 ms total across workers | not the bottleneck |
| stale tile misses | 28-88 per resize | width changes invalidate tiles |
| `view.apply` | 0.12 ms median | present thread |
| `view.commit` | 0.105 ms median | present thread |

The important negative results:

- Text measurement is not the cost: `text.measureCalls` is 11 on a resize pass; word widths are cached.
- Raster is not the cost: strips are 2-9 ms; the long `composite_raster_and_draw` span is not raster-bound.
- Height alone is not the cost; the tested vertical resize does no block work.

The cost is **line layout and the field/dependency graph for every line**, plus the style pass when a media query flips.

### 5.2 Scroll

89 scroll events, 16.74 ms median spacing, 0.17 ms median `scrollAt` handling.

| Measure | Value |
|---|---:|
| Scroll events | 89 |
| Median gap | 16.74 ms |
| p95 gap | 20.06 ms |
| `BrowserTab.scrollAt` median | 0.17 ms |
| `BrowserTab.scrollAt` max | 10.39 ms |
| Presents in scroll frame 8 | 98 |
| Raster work in scroll frame 8 | 11 of 65 events |
| `view.apply` median | 0.12 ms |
| `view.commit` median | 0.105 ms |

Steady-state scrolling is already cheap: the offset is applied, the present thread moves layers, and raster only runs when the 128 px tile step is crossed. The trace does not test scroll during a reflow, but the code shows why it would freeze: both wheel handling and layout are on the main thread.

### 5.3 Trace limits

- It records counters, not object lifetimes; it cannot prove why 1,773 nodes are all visited.
- It has no combined "scroll while resizing" scenario.
- The two large frames (6 and 46) are load/layout for the big page, not resize.
- The 120 ms preview debounce is visible only as the 125-174 ms delay between the last event and the next layout.

## 6. Gap against real engines

| Concern | Ideal | ToyStack | Gap |
|---|---|---|---|
| Scroll motion during layout | compositor thread/process | main thread | large |
| Scroll during JS | compositor thread/process | main thread | large |
| Resize event coalescing | latest size per frame | 307 events -> 15 layouts | already good |
| Resize preview | last complete frame, no distortion | non-uniform scale | small |
| Preview scheduling | frame clock, testable | 120 ms main-queue timer | small |
| Width reflow cost | one to two frames | 90-153 ms | large |
| Reflow during drag | progressive when affordable | never while events continue | medium |
| Present a mismatched frame | clip/pad, never stretch | preview stretch | small |
| Raster during resize | incremental / scaled | 28-88 stale tiles | small |

## 7. Improvement plan

Files that would change, and why:

| Phase | Files | Why |
|---|---|---|
| 0 | `Browser.swift`, `MeasureTime` call sites, `scripts/` | measure resize latency and presents per burst |
| 1 | `Browser.swift` | frame-driven preview, no DispatchWorkItem |
| 2 | `ContentPresenter.swift` | preview without text distortion |
| 3 | `LineLayoutPass.swift`, `BlockLayoutPass.swift` | stop re-placing reused lines; later, one text fragment per line |
| 4 | `Browser.swift` | optional live reflow during long drags |
| 5 | `Browser.swift`, `Frame.swift`, `ContentPresenter.swift` | scroll offset not blocked by layout |
| 6 | `ScrollTween.swift` | keyboard scroll by elapsed time |

### Phase 0 — Make the resize budget visible

Add counters in `Browser.resize` and after `render`:

- `resize.events` — count per burst.
- `resize.preview` — 1 when preview starts.
- `resize.layout.latency` — time from the last resize event to layout start.
- `resize.layout.duration` — measured layout time.
- `resize.stale` — frame dropped because the viewport changed before commit.
- `present.coalesced` — already exists; read it per burst.

Exit condition: a 30-event burst reproduces the current 90-153 ms layout and the 125-174 ms debounce in one trace.

### Phase 1 — Drive the preview from the frame clock

Current defects:

- `beginResizePreview` starts a main-queue timer per event.
- The timer competes with queued resize events and presents.
- Presents during a drag are per event, not per frame.

Proposed change in `Sources/Engine/Core/Browser.swift`:

```diff
-    private var resizePreviewWorkItem: DispatchWorkItem?
-    private var isResizePreview: Bool = false
+    private var resizePreviewDeadline: Date?
+    private var lastPreviewSize: CGSize?
     private let resizePreviewDelay: TimeInterval = 0.12
```

```diff
     public func resize(to size: CGSize, deferLayout: Bool = false) {
         windowSize = size
         for tab in tabs {
             tab.resize(width: size.width, height: size.height - topInset)
         }
-        guard deferLayout,
-            activeTab != nil,
-            estimatedFrameTime > FRAME_BUDGET * 2.0
-        else {
+        guard deferLayout, activeTab != nil else {
             cancelResizePreview()
             return
         }
-        beginResizePreview()
-    }
-
-    private func beginResizePreview() {
-        isResizePreview = true
-        resizePreviewWorkItem?.cancel()
-
-        let work: DispatchWorkItem = DispatchWorkItem { [weak self] in
-            guard let self else { return }
-            self.isResizePreview = false
-            if let tab: BrowserTab = self.activeTab {
-                self.setNeedsAnimationFrame(tab)
-            }
-        }
-        resizePreviewWorkItem = work
-        DispatchQueue.main.asyncAfter(
-            deadline: .now() + resizePreviewDelay,
-            execute: work
-        )
-        // Rebind the old content before AppKit applies the new view size.
-        // Without this, the layout present scales the old content directly
-        // and text stretches during the drag.
-        dispatchPresent(frameID: currentFrameID)
+        // Keep the old content visible while the pointer moves. The animation
+        // tick presents it once per frame and reflows one beat after the last
+        // event, so a slow page never lays out a size that is already stale.
+        if estimatedFrameTime > FRAME_BUDGET * 2.0 {
+            resizePreviewDeadline = Date().addingTimeInterval(resizePreviewDelay)
+        } else {
+            resizePreviewDeadline = nil
+        }
+        if let tab: BrowserTab = activeTab {
+            setNeedsAnimationFrame(tab)
+        }
     }
 
     private func cancelResizePreview() {
-        resizePreviewWorkItem?.cancel()
-        resizePreviewWorkItem = nil
-        isResizePreview = false
+        resizePreviewDeadline = nil
+        lastPreviewSize = nil
     }
```

```diff
     private func animationTick() {
         guard needsAnimationFrame else {
             return
         }
-        needsAnimationFrame = false
-        guard !isResizePreview else {
-            return
-        }
+        if let deadline: Date = resizePreviewDeadline {
+            if Date() < deadline {
+                if lastPreviewSize != windowSize {
+                    lastPreviewSize = windowSize
+                    dispatchPresent(frameID: currentFrameID)
+                }
+                return
+            }
+            cancelResizePreview()
+        }
+        needsAnimationFrame = false
         frameStartTime = Date()
         activeTab?.runAnimationFrame()
     }
```

The property `isResizePreview` and its guard are gone; the preview state is now just the deadline.

Why this is safe:

- The preview stays alive because `animationTick` returns without clearing `needsAnimationFrame`.
- Only one present happens per size change per tick, not one per event.
- The final layout starts on the first tick after the deadline, not from a competing main-queue timer.
- Fast pages never enter preview.

Exit condition: trace shows at most one preview present per tick; layout latency is still around 120 ms + one tick.

### Phase 2 — Preview without distorting text

The current preview scales `contentLayer` by `newSize / previousSize` (`ContentPresenter.swift:181`). That is why text stretches during a drag.

Option A (recommended): **clip the last complete frame at 1:1** and fill the new area with the canvas color. This is what Chromium's display compositor does after its 2026 resize fixes: if the frame does not match the window, clip the viewport to the frame, not stretch stale pixels.

```diff
         if preview, let previousSize, previousSize.width > 0, previousSize.height > 0 {
             contentLayer.backgroundColor = frame.viewport.canvasColor
             contentLayer.anchorPoint = CGPoint(x: 0, y: 0)
-            let base: CATransform3D = CATransform3DMakeScale(scale.page, scale.page, 1)
-            contentLayer.transform = CATransform3DScale(
-                base,
-                viewSize.width / previousSize.width,
-                viewSize.height / previousSize.height,
-                1
-            )
+            contentLayer.transform = CATransform3DMakeScale(scale.page, scale.page, 1)
             contentLayer.frame = CGRect(
                 x: 0,
                 y: frame.viewport.contentOffset,
                 width: previousSize.width,
                 height: previousSize.height
             )
             return
         }
```

Trade-off: when the window grows, the new area shows the canvas color until the reflow lands. No distorted text, no stale pixels.

Option B: **uniform scale** (fit, preserve aspect ratio). Better visual fill during shrink, but content still does not match the new layout and may letterbox. Use only if the gutter is unacceptable.

Do not keep the current non-uniform scale: it is the one behavior that is definitely wrong for text.

Exit condition: a screenshot taken mid-drag at a wider and a narrower size has no stretched glyphs; the preview present stays at ~0.1 ms.

### Phase 3 — Make the width reflow cheaper

This is the real fix. The trace says the final snap is 90-153 ms; no scheduler can make that disappear.

Two sub-steps, in order.

#### 3a. Reuse a line without re-placing its children

`resetLine` (`LineLayoutPass.swift:28`) clears `LineData`, including `placement`. It marks x/y/width/ascent/descent dirty. Even when a line's item range is unchanged, `childCountChanged` becomes true and `layoutLine` re-places every child.

Add a `reuseLine` path that keeps the placement, marks only `.width` and `.y`, and lets the existing `verticalOnly` branch move the line without touching each text child:

```diff
+    /// Keeps the line's placement data when only its frame moves. The
+    /// vertical-only path then shifts `inlineYOffset` instead of writing a
+    /// position for every text child.
+    @discardableResult
+    mutating func reuseLine(_ id: LayoutID, previous: LayoutID?) -> Bool {
+        let oldPrevious: LayoutID? = previousID(of: id)
+        var data: LineData = lineData(id)
+        data.paint.generation += 1
+        setKind(.line(data), at: id)
+        setPrevious(previous, of: id)
+        for field in [LayoutField.width, .y] {
+            markField(field, at: id)
+        }
+        return oldPrevious != previous
+    }
+
```

```diff
             if let line: LayoutID = reusable[index] {
-                let previousChanged: Bool = resetLine(line, previous: previous)
+                let previousChanged: Bool = reuseLine(line, previous: previous)
                 setLineChildrenField(
                     childrenIDs(of: line),
                     of: line,
                     previousChanged: previousChanged
                 )
                 lines.append(line)
                 previous = line
                 profiler.count("layout.inline.place.reusedLines")
                 continue
             }
```

Why it is correct: `layoutLine` reads `lineY` from the previous line and calls `setFrame`, so `.y` must stay dirty; `.x` only changes for centered/RTL lines and `widthMovesChildren` already forces a full placement there. Percentage-width embeds dirty their own width, and `childWidthChanged` forces placement in that case.

Exit condition: on a width change that keeps the line plan, `layout.line.place.placed.count` drops and `layout.line.place.skipped.count` rises; screenshots and `LayoutOracle` match the full layout.

#### 3b. Cut the per-word layout graph (design, not a small diff)

The traced page has 10,336 text layout objects for 1,443 inline blocks. Every line rebuild touches each word:

- `appendToLine` per word.
- `setFontAndPrevious` per word.
- one `TextLayout` child per word.
- one dependency edge set per word.

Real engines keep a text run and a **line fragment**, not a layout object per word. That is the structural reason their reflow is cheaper.

Proposed target:

- One inline text item per text node, with break positions.
- A line owns fragments `(run, start, end)`; a fragment is not a `LayoutID`.
- Paint reads the fragment and draws the substring.
- Hit-testing and accessibility use the same fragments.

Files: `InlineTextItem.swift`, `InlineTextRun.swift`, `TextLayoutPass.swift`, `BlockLayoutPass.swift`, `LayoutTree.swift`, `DisplayOp`/`PaintPass`, accessibility bounds.

This is a large phase. Do not start it before 3a and the oracle tests are stable.

Measured targets for the bench page:

- Width-only resize: layout 90-153 ms -> under 50 ms first, then under 33 ms.
- Once under 33 ms, remove preview for that page; the scheduler should let it reflow live.

### Phase 4 — Optional: reflow while the drag continues

Only after Phase 5 (scroll decoupling), because a 100 ms reflow on the main thread will otherwise freeze a scroll that is happening at the same time.

Policy:

- While previewing, if the drag has lasted more than `resizeReflowInterval` (e.g. 250 ms), run one render at the latest size.
- If a resize event arrived during that render, the rendered size is stale; keep the preview and do not present the stale reflow.
- Reset the interval after each render.

Sketch:

```diff
+    private var nextResizeReflow: Date = .distantPast
+    private let resizeReflowInterval: TimeInterval = 0.25
```

```diff
         if let deadline: Date = resizePreviewDeadline {
-            if Date() < deadline {
+            if Date() < deadline && Date() < nextResizeReflow {
                 if lastPreviewSize != windowSize {
                     lastPreviewSize = windowSize
                     dispatchPresent(frameID: currentFrameID)
                 }
                 return
             }
             cancelResizePreview()
+            nextResizeReflow = Date().addingTimeInterval(resizeReflowInterval)
         }
```

Risk: each render blocks input for 100 ms today. Gate it behind the layout-cost target from Phase 3.

### Phase 5 — Decouple scroll from layout

Short-term:

- Do not call `repaintForScroll()` synchronously from `Browser.applyScroll` on the input path. It paints a window (5-8 ms) when the scroll leaves the painted range. Move that paint to the next animation tick, or widen the paint window.
- Keep the direct offset + present path; the trace shows it is cheap.

Medium-term:

- Introduce a `ScrollPresentation` value that the present thread can read without the main actor. The main thread publishes the target offset; the present thread applies `contentLayer.frame`/placements. This is the same split as `cc`/WebKit/APZ, but inside one process.
- Non-fast scrollable regions (nested scrollers, scroll effects, JS listeners) can still round-trip to main; the viewport scroll should not.

Long-term:

- Threaded/async scroll like LadyBird's out-of-process compositor, or Chromium `cc`. This is the only way to keep scrolling at 60 Hz during a 100 ms reflow.
- ToyStack receives wheel events on the main run loop today (`NSEvent.addLocalMonitorForEvents`). True decoupling needs an input path that does not depend on main-thread scheduling (an event tap on a dedicated thread, or a compositor process boundary).

### Phase 6 — Animate keyboard scroll by time, not by frame count

`ScrollTween` counts 12 frames (`ScrollTween.swift`), and `aim` resets the count on every key repeat. Two consequences:

- The duration follows the tick rate, not the clock. A slow tick stretches the scroll; a faster clock shortens it.
- Repeating an arrow key restarts the ease-out from zero, so held keys feel like a series of small decelerations.

Use elapsed time for the animation and keep the remaining target continuous:

```diff
 class ScrollTween {
     private var start: CGFloat
     private var target: CGFloat
-    private let totalFrames: Int
+    private let duration: TimeInterval
     private let easing: Easing
-    private var currentFrame: Int = 0
+    private var startedAt: Date = Date()
+    private var finished: Bool = false
 
     init(
         from start: CGFloat,
         to target: CGFloat,
-        totalFrames: Int = 12,
+        duration: TimeInterval = 0.2,
         easing: Easing = .easeOut
     ) {
         self.start = start
         self.target = target
-        self.totalFrames = totalFrames
+        self.duration = duration
         self.easing = easing
     }
 
     func aim(from current: CGFloat, by delta: CGFloat, within bounds: ClosedRange<CGFloat>) {
         start = current
         target = min(max(target + delta, bounds.lowerBound), bounds.upperBound)
-        currentFrame = 0
+        startedAt = Date()
+        finished = false
     }
 
     func nextValue() -> CGFloat? {
-        currentFrame += 1
-        if currentFrame > totalFrames { return nil }
-        let t: Double = Double(currentFrame) / Double(totalFrames)
+        if finished { return nil }
+        let t: Double = min(Date().timeIntervalSince(startedAt) / duration, 1)
+        if t >= 1 { finished = true }
         let eased: Double = easing.apply(t)
         return start + (target - start) * CGFloat(eased)
     }
 }
```

`Frame.runAnimationFrame` already calls `nextValue()` once per tick; a time-based tween keeps the same call site. The eye check is a held arrow key: the scroll should move at a constant wall-clock speed and should not stutter on a slow frame.

Exit condition: trace `ScrollTween` start/end timestamps are ~200 ms apart regardless of frame duration; repeated key events do not visible restart the easing.

## 8. Acceptance criteria

| Goal | Metric | Where |
|---|---|---|
| Preview is frame-paced | <= 1 preview present per tick | trace `present` counters |
| Preview does not distort | no glyph stretch at 3 widths | screenshot mid-drag |
| Reflow starts at latest size | no layout for an intermediate size | trace `resize.*` |
| Reflow cost | width-only resize on `www/bench/large.html` < 50 ms, then < 33 ms | `profile.layout` |
| No stale frame | no present with a viewport different from the window | `resize.stale` = 0 |
| Scroll unaffected by resize | scroll events still 16.7 ms apart during a reflow | combined trace |
| Correctness | incremental == full layout | `LayoutOracleTests`, screenshots |

## 9. Risks

- Removing the non-uniform preview changes the visual during a drag; product decision, not a correctness one.
- `reuseLine` can under-invalidate if a line's children moved without a width/y change. The oracle and the RTL/centered/percentage-image tests are the guard.
- Reflow during a drag can starve input on the current main-thread model; do not enable it before scroll is decoupled.
- One-fragment-per-line text is a large refactor; keep it behind the existing incremental/full oracle.
- The trace is GUI-only; reproduce with a combined scroll+resize scenario before claiming scroll is fixed.

## 10. References

- Chromium `cc` input handling: <https://github.com/chromium/chromium/blob/main/cc/input/README.md>
- Chromium resize behavior (clip the viewport to the frame, no stale gutter): <https://www.electronjs.org/blog/tech-talk-window-resize-behavior>
- WebKit async scrolling: <https://docs.webkit.org/Ports/WebKitGTK%20and%20WPE%20WebKit/Graphics.html>
- Gecko APZ: <https://github.com/mozilla/gecko-dev/blob/master/gfx/docs/AsyncPanZoom.rst>
- Servo architecture: <https://book.servo.org/architecture/overview.html>
- LadyBird async scrolling, May 2026: <https://ladybird.org/newsletter/2026-05-31/>
