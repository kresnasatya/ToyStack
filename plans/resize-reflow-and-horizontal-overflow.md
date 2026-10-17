# Note — window resize: late reflow + horizontal overflow

Status: **diagnosed, not implemented**. Two independent defects that happen to show
up together when you drag the window edge.

Test page: `www/ch11/resize-check.html` (created here). Real-world case: the same
two defects on <https://browser.engineering/visual-effects.html>.

## What you see

| Symptom | When |
|---|---|
| Content keeps the old width while you drag, then snaps a moment after you let go | every resize on a long page |
| Content sticks out past the right edge and you cannot reach it | narrow windows, any page with a wide image / `<pre>` |
| While dragging, the stale picture is cut off on the right (narrowing) or leaves a blank strip (widening) | same |

## How to reproduce

```bash
# overflow, offline
swift run -c release ToyStackHeadless \
  "file://$PWD/www/ch11/resize-check.html" \
  --screenshot /tmp/rc-500.png --width 500 --height 1400 --scale 1

# overflow on the real page (cover image is 1428px wide, viewport 500px)
swift run -c release ToyStackHeadless \
  https://browser.engineering/visual-effects.html \
  --screenshot /tmp/ve-500.png --width 500 --height 600 --scale 1
```

Then rebuild with a screen recording:

```bash
ffmpeg -f avfoundation -i "2" -t 20 /tmp/resize.mov   # drag the window edge during it
```

`www/ch11/resize-check.html` at 500px wide shows both: the 1428px image overflows,
and the `<pre>` line runs off the right edge.

---

## Symptom 1 — reflow only after you let go

Three things add up. They are independent; fixing one does not fix the others.

### Cause A (the big one): the tick timer is frozen during a live resize

The engine has no timer of its own. Everything — "is the page dirty?" — is decided
once per tick, on a one-shot `Timer` rescheduled every frame:

- `Sources/Engine/Core/Browser.swift:143` `scheduleNextFrame()`
- `Sources/Engine/Core/Browser.swift:148` `Timer.scheduledTimer(withTimeInterval:repeats:block:)`

`Timer.scheduledTimer` puts the timer in the run loop's **default mode**. While you
hold the mouse and drag a window edge, AppKit runs a nested run loop in
`NSEventTrackingRunLoopMode` only. A timer registered in default mode does not fire
there — so `animationTick()` (`Browser.swift:165`) never runs, `render()` is never
reached, and `Frame.setNeedsRender()` (`Frame.swift:1247`) just accumulates flags.
The reflow is already queued; the tick that would run it is asleep.

Measured, with a 0.5s simulated drag (`NSEventTrackingRunLoopMode` added to the main
run loop's common modes, exactly as AppKit does):

```
during 'drag' (NSEventTrackingRunLoopMode): default-mode=0   common-modes=31
after release (kCFRunLoopDefaultMode)     : default-mode=32  common-modes=62
```

The default-mode timer fires **zero** times during the drag. After release both
catch up. That is the "delay": not slow layout, but no tick at all until the drag
ends (the same reason scroll-animations and cursors freeze during a drag in AppKit
apps that use `NSTimer` for their heartbeat).

### Cause B: one tick is a full style + layout + paint, and resize asks for all three

`BrowserTab.resize` (`Sources/Engine/Core/BrowserTab.swift:203`) calls
`rootFrame.setNeedsRender()`, and `setNeedsRender` sets `needsStyle = true`
(`Frame.swift:1247-1252`). So every resize event re-runs:

- the **whole cascade** (`Frame.render()` → `if needsStyle`, `Frame.swift:654-736`):
  re-sort the rules, rebuild `RuleIndex`, re-run the `:has()` precompute, snapshot
  every node's style, re-cascade, re-diff for transitions
- a **brand new layout tree** — `DocumentLayout(node: nodes)` then `doc.layout(...)`
  (`Frame.swift:743-744`), so no layout object, line box, or cached font survives
- the **whole paint list** (`Frame.paint()`, `Frame.swift:756-769`) — rebuilding every
  display item, for every node (see Round 2 below: the bulk of this is one
  `NSRegularExpression` compiled per node, not word measurement)
- the whole accessibility tree (`BrowserTab.runAnimationFrame`, `BrowserTab.swift:180-187`)

One full pass over `visual-effects.html` (~1000 elements, ~9700 words), release
build, profiler on, sampled per resize-like render:

```
BrowserTab.style   ~16–33 ms
BrowserTab.layout  ~26–45 ms
BrowserTab.paint   ~80 ms
BrowserTab.a11y    ~16–18 ms
composite_raster   ~35–115 ms
```

≈ **170–290 ms per resize event** in release, and every reflow also invalidates the
raster, so `composite_raster_and_draw` re-runs too. Style is needed on resize only
because `@media (min|max)-width` results depend on the width
(`Frame.swift:678-684`, `MediaFeatures.swift:19-28`), but the code re-cascades
whether or not a breakpoint actually moved.

### Cause C: presenting waits for a raster round trip, and stale frames are dropped

`Browser.commit` → `scheduleRasterAndDraw` (`Browser.swift:246`) hands the frame to
`RasterScheduler`, which runs off the main thread and replaces any pending job
(`RasterScheduler.swift:20-27`). While a job is in flight the main thread refuses to
queue another (`Browser.swift:251-253`). `ContentPresenter` does the same on the
present side and counts the frames it threw away (`ContentPresenter.swift:25-53`,
`present`/`dropped` counter).

So: while you drag, intermediate sizes are silently discarded and each surviving one
costs a full pass plus a round trip before anything appears. That is why the content
"catches up" in one jump rather than tracking the mouse.

### Cause D (small): the stale bitmap is re-framed, not rescaled

During the drag the presented frame is old, but `ContentPresenter.applyImage`
(`ContentPresenter.swift:194-214`) re-sets `contentLayer.frame` to the **new**
`viewSize.width` while `contentLayer.contentsGravity = .topLeft`
(`BrowserContentView.swift:18`) and `layer?.masksToBounds = true`
(`BrowserContentView.swift:16`). The old picture keeps its old pixel size and is
clipped at the new edge: narrowing cuts the right side off, widening leaves a blank
strip. That is the visual half of "some parts overflow in horizontal".

### Fixes for symptom 1 (see "Changes", steps 1–3)

1. Register the tick timer in `.common` mode (or drive it from a `CVDisplayLink`).
2. Resize invalidates **layout**, not style — unless a media query flipped.
3. Later: incremental layout, so a width change does not rebuild the whole tree.

Steps 1, 2 and 4 have been applied; Round 2 at the bottom of this file is what the
trace says about the result and what is left.

---

## Symptom 2 — horizontal overflow

The window has no horizontal axis at all. Four separate gaps:

### 2a. `max-width` on an element is ignored

`browser.engineering` has `img { max-width: 100%; }` (`book.css:215`). ToyStack parses
it (declarations are stored generically, `ApplyStyle.swift:55-58`) but nothing reads
`node.style["max-width"]`:

- `max-width`/`min-width` only exist as **media features**, not declarations:
  `CSSParser.swift:404-419` (`@media (max-width: 800px)`), `MediaFeatures.swift:24-25`.
- A block's width is `px`-only, everything else falls back to the parent
  (`BlockLayout.swift:55-59`).
- An image's width is its intrinsic size (`ImageLayout.swift:9-19`, applied at
  `ImageLayout.swift:25`). `addImage` (`BlockLayout.swift:343-353`) only starts a new
  line if it does not fit; it never shrinks it. Same for `addIframe`
  (`BlockLayout.swift:355-365`) and `addCanvas` (`BlockLayout.swift:367-377`).

Net effect: a 1428px image in a 500px window draws at 1428px. Real engines honour
`max-width: 100%` and keep the aspect ratio — see `book.css:215`.

### 2b. `overflow: auto` does not create a scroll container

`book.css:31-32` has `pre { overflow: auto; }` for wide code lines. ToyStack only
promotes `overflow-y/x: scroll` to `overflow: scroll`
(`ApplyStyle.swift:80-84`), so `auto` is not a scroll container at all. `pre` also has
`white-space: pre` (`browser.css`), i.e. `WhiteSpaceMode.wraps == false`
(`WhiteSpaceMode.swift:28`), so it never wraps — the line just runs off the edge.
Our `resize-check.html` reproduces it.

### 2c. The existing scroll container is vertical-only

`BlockLayout` tracks `contentHeight` but no `contentWidth` (`BlockLayout.swift:26-27`,
`168-171`), and `Frame.scrollAt` compares `contentHeight - height` only
(`Frame.swift:1003-1017`). `BlockLayout.paintScrollbar` draws one vertical bar
(`BlockLayout.swift:494-503`).

### 2d. The window has no horizontal scrollbar

`Browser.activeSidebar` builds only the vertical bar
(`Browser.swift:64-80`, geometry from `Scrollbar.swift`), and the content layer clips
(`BrowserContentView.swift:16`). So anything wider than the window is unreachable —
worse than a real browser's horizontal scrollbar.

### Fixes for symptom 2 (see "Changes", steps 4–5)

4. Read `max-width` (and `%`/`px` widths) for replaced elements — one shared length
   helper, used by image/iframe/canvas.
5. Make `overflow: auto|scroll` a per-axis scroll container and give the window a
   horizontal scrollbar.

---

## How real browser engines solve this

Each bullet answers one cause above.

**1. The frame heartbeat is not a default-mode `NSTimer`.** Browsers are driven by a
vsync callback — Chromium's `viz` `BeginFrame` on the display compositor, Firefox's
refresh driver on the vsync thread. It is a separate ongoing signal, not a run-loop
timer, so mouse tracking on the UI thread cannot starve it. On macOS the equivalent is
`CVDisplayLink`/`CADisplayLink`, or at minimum a timer added in `.common` mode as in
step 1.

**2. Resize is a layout-only invalidation, plus a media-query check.** Browsers keep a
`MediaQueryList` per query and re-evaluate those objects when the viewport changes
(`window.matchMedia`, `addListener`/`change`). If no query verdict flips, no style is
recomputed — the cascade is skipped entirely and only layout runs. Crossing a
breakpoint invalidates just the rules behind that query. Blink does this through
`MediaQueryEvaluator` + rule invalidation; step 2 is a small version of it.

**3. Layout is incremental, not a rebuild.** A browser keeps the previous layout tree
and marks subtrees dirty ("layout roots"). A resize sets the root as dirty but reuses
everything whose input did not change: line boxes (text is re-broken only when the
available width actually changes and only from the first affected line), shaped text
runs, image sizes, and any subtree with a fixed/known size. Blink's LayoutNG keeps a
fragment tree and relayout boundaries for exactly this; Gecko has `nsIFrame` reflow
with dirty bits. ToyStack throws the tree away (`Frame.swift:743-744`), which is the
cheapest thing to write and the most expensive to run.

**4. Overflow is a first-class, per-axis concept.** `overflow-x`/`overflow-y` create
0–2 independent scroll containers, each with its own `scrollLeft`/`scrollTop`,
scrollable-overflow rect, and scrollbar; `auto` means "scrollbar only if needed".
Replaced elements resolve width against min/max/percentage, and `max-width: 100%`
clamps to the containing block while preserving the intrinsic ratio. Steps 4–5 pull
ToyStack toward that model.

**5. Presentation is decoupled and event-driven.** The compositor owns the pixels and
presents the last committed frame every vsync. While the main thread is busy, the
compositor can present, scroll, or even stretch the previous frame
(Chromium's resize/checkerboard behaviour) so the window never looks frozen. Resize
events are coalesced to at most one layout per frame. ToyStack already has a
background raster thread and a coalescing presenter — the missing part is that the
*tick* (Cause A) never fires, so neither of them is ever asked to act.

---

## Changes

| File | Why |
|---|---|
| `Sources/Engine/Core/Browser.swift` | tick timer → `.common` mode so it survives a live resize |
| `Sources/Engine/Core/BrowserTab.swift` | skip no-op resizes; ask for a *viewport* resize instead of a full render |
| `Sources/Engine/Core/Frame.swift` | `setNeedsViewportResize()` + remember media-query verdicts |
| `Sources/Engine/Layouts/LengthPx.swift` (new) | one place that understands `px` / `%` lengths |
| `Sources/Engine/Layouts/ImageLayout.swift` | clamp the image to `max-width`, keep the ratio |
| `Sources/Engine/Layouts/BlockLayout.swift` | measure the image at its clamped width so the line break is right |
| `Sources/Engine/Style/ApplyStyle.swift` (step 5) | treat `overflow: auto` as a scroll container |
| `Sources/Engine/Layouts/BlockLayout.swift`, `Frame.swift` (step 5) | per-axis scroll offset + horizontal scrollbar |
| `Sources/Engine/Style/CSSValueParser.swift` (step 6) | stop recompiling the transform regex per node |
| `Sources/Engine/Core/BrowserTab.swift`, `Browser.swift` (step 7) | stop rebuilding the accessibility tree on every layout |
| `Sources/Engine/Display/DisplayCommand.swift` (step 8) | cache the per-type hash parts instead of per item |

Steps 1–4 each leave the project building and are independent. Step 5 is the big one
and gets its own plan; it is sketched at the end.

### Step 1 — keep the tick alive during a live resize

`Sources/Engine/Core/Browser.swift:143-157`

```diff
     private func scheduleNextFrame() {
         let now: Date = Date()
 
         nextFrameTime = max(nextFrameTime + FRAME_BUDGET, now)
         let delay: TimeInterval = nextFrameTime.timeIntervalSinceNow
-        animationTimer = Timer.scheduledTimer(
-            withTimeInterval: max(0, delay), repeats: false,
-            block: {
-                [weak self] _ in
-                Task { @MainActor in
-                    self?.animationTick()
-                    self?.scheduleNextFrame()
-                }
-            })
+        let timer: Timer = Timer(timeInterval: max(0, delay), repeats: false) {
+            [weak self] _ in
+            Task { @MainActor in
+                self?.animationTick()
+                self?.scheduleNextFrame()
+            }
+        }
+        // `.common`, not `.default`: while you drag a window edge the run loop
+        // only runs NSEventTrackingRunLoopMode, where a default-mode timer is
+        // starved — the page then re-lays out only after you let go.
+        RunLoop.main.add(timer, forMode: .common)
+        animationTimer = timer
     }
```

`stopAnimationTimer` (`Browser.swift:159`) still works: `Timer.invalidate()` removes
it from every mode.

Option B, the closer-to-a-real-engine version: replace the repeating timer with a
`CVDisplayLink` on the display's vsync and hop to the main actor per callback. More
code, and it needs a display to be attached (it does not run in `ToyStackHeadless`),
which is why the `.common` timer is the recommended first step.

### Step 2 — resize re-lays out; only a media-query flip needs style

First, drop no-op resizes. `Sources/Engine/Core/BrowserTab.swift:203-209`

```diff
     public func resize(width: CGFloat, height: CGFloat) {
+        guard width != tabWidth || height != tabHeight else { return }
         tabWidth = width
         tabHeight = height
         rootFrame.frameWidth = width
         rootFrame.frameHeight = height
-        rootFrame.setNeedsRender()
+        rootFrame.setNeedsViewportResize()
     }
```

Then the new invalidation and the bookkeeping it needs. `Sources/Engine/Core/Frame.swift`

```diff
     var needsRender: Bool = false
     var needsStyle: Bool = false
     var needsLayout: Bool = false
     var needsPaint: Bool = false
+    /// Every non-nil `@media (...)` text in the cascade, and the verdict each one
+    /// had at the last style pass. Lets a resize tell "nothing style-visible
+    /// changed" from "a breakpoint flipped".
+    private var mediaQueries: Set<String> = []
+    private var mediaVerdicts: [String: Bool] = [:]
```

```diff
             let sortedRules: [(String?, any CSSSelector, [String : String])] = rules.sorted(by: { cascadePriority($0) < cascadePriority($1) })
             let ruleIndex: RuleIndex = RuleIndex(rules: sortedRules)
+            mediaQueries = Set(sortedRules.compactMap({ $0.0 }))
             profiler.count("style.rules", by: sortedRules.count)
```

```diff
-            let media: MediaFeatures = MediaFeatures(
-                preferences: ColorPreferences(
-                    prefersDark: tab?.prefersDark ?? false,
-                    usesForcedColors: tab?.forcedColors ?? false
-                ),
-                frameWidth: frameWidth / zoom
-            )
+            let media: MediaFeatures = currentMedia()
+            recordMediaVerdicts(media)
             let ancestorKeys: AncestorSelectorKeys = AncestorSelectorKeys()
```

and in the Invalidation section (`Frame.swift:1245`), next to `setNeedsLayout`:

```diff
+    /// A viewport resize always needs a new layout. Style has to run again only
+    /// when the new width flips a `@media (min|max)-width` query — otherwise the
+    /// cascade would repeat on every pixel of a drag for nothing.
+    func setNeedsViewportResize() {
+        if mediaQueryVerdictsChanged() {
+            setNeedsRender()
+        } else {
+            setNeedsLayout()
+        }
+    }
+
+    private func currentMedia() -> MediaFeatures {
+        MediaFeatures(
+            preferences: ColorPreferences(
+                prefersDark: tab?.prefersDark ?? false,
+                usesForcedColors: tab?.forcedColors ?? false
+            ),
+            frameWidth: frameWidth / zoom
+        )
+    }
+
+    private func recordMediaVerdicts(_ media: MediaFeatures) {
+        mediaVerdicts = mediaQueries.reduce(into: [:]) { verdicts, query in
+            verdicts[query] = media.matches(query)
+        }
+    }
+
+    private func mediaQueryVerdictsChanged() -> Bool {
+        guard !mediaQueries.isEmpty else { return false }
+        let media: MediaFeatures = currentMedia()
+        var flipped: Bool = false
+        for query in mediaQueries {
+            let now: Bool = media.matches(query)
+            if mediaVerdicts[query] != now {
+                flipped = true
+                mediaVerdicts[query] = now
+            }
+        }
+        return flipped
+    }
+
     func setNeedsRender() {
```

Notes:

- `setNeedsLayout()` already sets `needsRender = true` and requests a frame
  (`Frame.swift:1254-1259`), so the tick still picks it up.
- `prefersDark` / `forcedColors` flips still go through `setNeedsRender`
  (`BrowserTab.swift:47-57`) — they change media verdicts too, but they are rare and
  cheap to re-cascade.
- Option A (smaller, but keeps the waste): leave `setNeedsRender()` in `resize` and
  instead cache the sorted rules + `RuleIndex` + `:has()` precompute across renders.
  That removes `BrowserTab.style.rules`/`style.has` from the per-resize cost but still
  re-cascades every node. Option B above (shown) is barely more code and removes the
  cascade itself, so it is the recommendation.

### Step 3 — (later) incremental layout

Not part of this change. The reason to note it here: even after step 2 a resize costs
a full layout + paint (~110 ms release on that page), because
`Frame.swift:743-744` builds a new `DocumentLayout` every time. The real fix is to keep
the previous tree and reuse it per subtree — a much larger change (dirty bits on
`LayoutObject`, a stable layout root, reuse of `LineLayout`/`TextLayout` when the
available width is unchanged). Worth its own plan.

### Step 4 — honour `max-width` for replaced elements

New file, so both layout types that need it can share it.

`Sources/Engine/Layouts/LengthPx.swift`

```swift
import CoreGraphics

// MARK: - LengthPx

/// A CSS length resolved to device pixels.
///
/// Only `px` and `%` are understood; anything else (`auto`, `em`, `ch`, ...)
/// returns `nil` so the caller keeps whatever default it had. `available` is the
/// containing block's width in device pixels.
func lengthPx(_ css: String?, available: CGFloat, zoom: CGFloat) -> CGFloat? {
    guard let css else { return nil }
    let trimmed: String = css.trimmingCharacters(in: .whitespaces)
    if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
        return available * CGFloat(pct) / 100
    }
    if trimmed.hasSuffix("px"), let px = Double(trimmed.dropLast(2)) {
        return CGFloat(px) * zoom
    }
    return nil
}
```

`Sources/Engine/Layouts/ImageLayout.swift:9-28`

```diff
     static func displaySize(for el: Element) -> (width: Double, height: Double) {
         ...
         return (intrinsicW, intrinsicH)
     }
 
+    /// Width the image actually takes: its intrinsic size, clamped by `max-width`
+    /// (which is how `img { max-width: 100% }` and every page that uses it work).
+    static func usedWidth(for el: Element, available: CGFloat, zoom: CGFloat) -> CGFloat {
+        let intrinsic: CGFloat = CGFloat(displaySize(for: el).width) * zoom
+        guard let limit = lengthPx(el.style["max-width"], available: available, zoom: zoom) else {
+            return intrinsic
+        }
+        return min(intrinsic, limit)
+    }
+
+    /// Height at `usedWidth` that keeps the intrinsic ratio, so clamping the width
+    /// does not squash the picture.
+    static func usedHeight(for el: Element, usedWidth: CGFloat, zoom: CGFloat) -> CGFloat {
+        let size: (width: Double, height: Double) = displaySize(for: el)
+        let ratio: AspectRatio? =
+            AspectRatio(css: el.style["aspect-ratio"])
+            ?? AspectRatio(intrinsicWidth: size.width, intrinsicHeight: size.height)
+        guard let height = ratio?.height(forWidth: Double(usedWidth / zoom)) else {
+            return CGFloat(size.height) * zoom
+        }
+        return CGFloat(height) * zoom
+    }
+
     override func layout() {
         super.layout()
         guard let el = node as? Element else { return }
-        let size: (width: Double, height: Double) = ImageLayout.displaySize(for: el)
-        width = scaled(CGFloat(size.width))
-        imgHeight = scaled(CGFloat(size.height))
+        let usedWidth: CGFloat = ImageLayout.usedWidth(for: el, available: parent!.width, zoom: zoom)
+        width = usedWidth
+        imgHeight = ImageLayout.usedHeight(for: el, usedWidth: usedWidth, zoom: zoom)
         height = max(imgHeight, font.linespace)
     }
```

`Sources/Engine/Layouts/BlockLayout.swift:343-345` — the line break must use the same
clamped width, otherwise the image wraps as if it were still 1428px wide:

```diff
     private func addImage(_ node: Element) {
-        let w: CGFloat = scaled(CGFloat(ImageLayout.displaySize(for: node).width))
+        let w: CGFloat = ImageLayout.usedWidth(for: node, available: width, zoom: zoom)
         if cursorX + w > width { newLine() }
```

`parent!.width` inside `ImageLayout.layout()` is the `LineLayout` the image sits in
(`LineLayout.swift:26`), i.e. the containing block width — the same number `addImage`
passed in, so the two agree.

`addIframe` (`BlockLayout.swift:355-358`) and `addCanvas` (`BlockLayout.swift:367-370`)
are the same two-line change if you want them clamped too; their sizes come from
`IframeLayout.displaySize` / `CanvasLayout.contentSize`.

Option B: resolve a full width chain (`auto`/`%`/`min-width`/`max-width`, in the right
order, per CSS 2.1 §10.3) in one place and use it for every box. Correct, but it is a
containing-block model change with much wider blast radius. Step 4 (shown) fixes the
case that actually bites — images — and leaves the cascade of `width` alone.

### Step 5 — (later, own plan) real `overflow: auto|scroll` with a horizontal axis

Minimum shape of the change, to be written up properly before touching code:

1. `ApplyStyle.swift:80-84` — treat `auto` like `scroll` (both keywords mean "a scroll
   container, scrollbar when needed").
2. `BlockLayout` — track `contentWidth` (the widest line/paint rect inside the box)
   next to `contentHeight` (`BlockLayout.swift:26-27`), and a `scrollOffsetX`
   alongside `scrollOffset`.
3. `Frame.scrollAt` (`Frame.swift:1003-1017`) — route a wheel/trackpad delta to the
   horizontal offset when the delta is mostly horizontal, and keep the existing
   vertical maths.
4. `BlockLayout.paintScrollbar` (`BlockLayout.swift:494-503`) — second bar on the
   bottom edge when `contentWidth > width`.
5. `Browser.activeSidebar`/`PresentedViewport` — a window-level horizontal bar, plus a
   horizontal `scroll` value in `ScrollState`.

Steps 2c/2d are the reason "some parts are overflow horizontally" in the current
build: with no horizontal scroll container anywhere, the only outcome is clipping.

---

## Verification

1. **Timer (step 1).** Add a temporary `print("tick")` in `animationTick`, rebuild,
   and hold the window edge: ticks should keep appearing during the drag. Before the
   change they stop.
2. **Cost (step 2).** Run the headless screenshot and read `browser.trace` for
   `BrowserTab.style` / `BrowserTab.layout`:

   ```bash
   python3 -c "
   import json
   d=json.load(open('browser.trace'))
   evs=[e for e in d['traceEvents'] if e.get('ts') is not None]
   stack={}
   for e in sorted(evs,key=lambda e:e['ts']):
       nm=e.get('name'); ph=e.get('ph')
       if nm in {'BrowserTab.style','BrowserTab.layout','BrowserTab.paint'}:
           if ph=='B': stack[nm]=e['ts']
           elif ph=='E' and nm in stack: print('%8.2fms  %s' % ((e['ts']-stack.pop(nm))/1000, nm))
   "
   ```

   Resizing with no breakpoint left should show `layout` but no `style`.
3. **Media queries still work.** `www/ch15/example15-media-query.html`, dragged across
   its breakpoint, must still restyle. This is what step 2's verdict check protects.
4. **Overflow (step 4).**

   ```bash
   swift run -c release ToyStackHeadless "$PWD/www/ch11/resize-check.html" \
     --screenshot /tmp/fixed.png --width 500 --height 1400 --scale 1
   ```

   The image should now be 500px wide (minus the `HSTEP` gutters) with its aspect
   ratio intact. The `<pre>` still overflows — that is step 5's job.
5. **No regression on the real page.** `visual-effects.html` at 800px and 500px: the
   layout should not shift at 800 (that page's breakpoints are 800/1150/1350, so 500
   and 800 cross different ones — check both).

---

# Round 2 — what `browser.trace` says after steps 1, 2 and 4

Run: the real `ToyStack` app (debug build, `Profiler` on), 27.5s, load + several drags
+ a scroll. `browser.trace` at the repo root. Numbers below are all from that file.

## Step 1 worked

`BrowserTab.layout` ran **23 times**, `BrowserTab.style` only **4**, `BrowserTab.paint`
22 times. Four of those 23 layouts form a burst during a single drag, ~240–272ms
apart:

```
10794.6ms  layout 70.4ms → a11y 37.1 → paint 122.5 → composite 254.7
11034.1ms  layout 71.3ms   (next tick starts 239.5ms after the previous one)
11276.1ms  layout 71.3ms
11509.6ms  paint 122.9ms   (last one of the burst)
```

Before the change that burst would have been a single layout after the mouse came up.
The tick now survives the tracking run loop, and 19 of the 23 layouts ran with **no
style pass** — so step 2's media-verdict check is doing its job. `style` appears only
at 14685ms and 17940ms, where the drag crossed a real `@media` breakpoint.

Also clean: nothing regressed in the raster/present path — `present` reports
`dropped: 0` for all 173 presents, and the scroll section at the end shows composites
of 8–20ms (`tiles {hits: 108, misses: 0}`).

Remaining: **one tick is still ~230ms of main-thread work** (layout 70 + a11y 37 +
paint 122), so a drag runs at ~4 reflows/second in this build. That is now a cost
problem, not a scheduling problem.

## What the cost actually is

`BrowserTab.a11y` (37ms) and `BrowserTab.paint` (122ms) were both unattributed in
Round 1, so I sampled a render of a long page (3000 paragraphs, debug build,
`sample` at 1ms — 1640 main-thread samples):

| Branch | Samples | Share |
|---|---|---|
| `Frame.paint()` → `paintTree` (`BrowserTab.swift:188`) | 1186 | **72%** |
| `frame.runAnimationFrame()` → style/layout (`BrowserTab.swift:178`) | 340 | 21% |
| a11y tree build (`BrowserTab.swift:183`) | 83 | 5% |

and inside paint:

```
Frame.paint()                                   1186
└ paintTree                                       1185   PaintTree.swift:38
  └ LayoutObject.paintEffects(_:)                  815   LayoutObject.swift:25
    └ paintBrowserVisualEffects(node:items:rect:)  678   BrowserVisualEffect.swift:36
      └ static CSSValueParser.transform(_:)        552   CSSValueParser.swift:29   ← 34% of the whole main thread
        └ NSRegularExpression.__allocating_init      550
          └ icu::RegexPattern::compile ...           499
```

### Step 6 — `CSSValueParser.transform` compiles a regex on every call

`Sources/Engine/Style/CSSValueParser.swift:27-37` builds `NSRegularExpression(pattern:)`
per call. `paintBrowserVisualEffects` calls it for **every node**
(`BrowserVisualEffect.swift:36`) — and does so *before* the `guard` that returns early
for the ~99% of nodes that have no transform at all:

```swift
let translation: CGPoint? = CSSValueParser.transform(node.style["transform"] ?? "")
...
guard borderRadius > 0 || blurRadius > 0 || opacity < 1
    || (blendMode != nil && blendMode != .normal)
    || translation != nil || animated
else { return items }
```

So a plain page pays one ICU regex compile per node per paint. The same call is also
in `LayoutObject.absoluteBounds()` (`LayoutObject.swift:69`) and
`LayoutObject.hitTest` (`LayoutObject.swift:36`), which is where the a11y build's 37ms
goes (`AccessibilityNode.computeBounds` → `absoluteBounds` → regex, visible in the
sample). It is one bug showing up in three hot paths.

`Sources/Engine/Style/CSSValueParser.swift`

```diff
 enum CSSValueParser {
+    /// Compiled once. `NSRegularExpression` construction is handed to ICU, which
+    /// parses the pattern and builds a matcher — ~7.6µs, measured. `transform` is
+    /// called once per node in paint, in accessibility bounds and in hit-testing,
+    /// so doing that per call was the single hottest line on the main thread.
+    private static let translatePattern: NSRegularExpression? = try? NSRegularExpression(
+        pattern: #"translate\((-?[0-9.]+)px,\s*(-?[0-9.]+)px\)"#
+    )
+
     static func splitOutsiteParentheses(_ value: String, separator: Character) -> [String] {
```

```diff
     static func transform(_ value: String) -> CGPoint? {
-        let pattern: String = #"translate\((-?[0-9.]+)px,\s*(-?[0-9.]+)px\)"#
-        guard let regex = try? NSRegularExpression(pattern: pattern),
+        // Most nodes have no `transform` at all: bail before touching the regex.
+        guard value.contains("translate("), let regex = translatePattern,
             let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
```

Expected: paint roughly halves in a debug build (the 552 samples are 45% of paint).
Option B is to delete the regex entirely — `transform` only ever matches
`translate(<n>px, <n>px)`, and the file's other parsers (`blur`, `outlineWidth`,
`backgroundImageURL`) are already hand-written string code. Option A above is two
lines and keeps the exact same accepted syntax, so it is the recommendation.

### Step 7 — the accessibility tree is rebuilt on every layout, even when a11y is off

`Frame.render()` sets `tab?.needsAccessibility = true` in the layout block
(`Frame.swift:747`) and `BrowserTab.runAnimationFrame` rebuilds the whole tree
unconditionally (`BrowserTab.swift:180-187`). The only consumers are gated on
`accessibilityIsOn` (`Browser.swift:986`, `1055`) and `pendingHover`, which itself is
only ever set when a11y is on (`Browser.swift:1054-1057`). So with a11y off this is
37ms per layout — 5% of main-thread time — thrown away, on top of the regex cost
inside it.

Option A — two lines, stops the waste when a11y is off.

`Sources/Engine/Core/BrowserTab.swift:180`

```diff
-        if needsAccessibility {
+        if needsAccessibility, browser?.accessibilityIsOn == true {
```

`Sources/Engine/Core/Browser.swift:1046`

```diff
     public func toggleAccessibility() {
         accessibilityIsOn = !accessibilityIsOn
         if accessibilityIsOn { hasSpokenDocument = false }
+        activeTab?.needsAccessibility = true
         hoveredA11yNode = nil
```

Option B (recommended) — invalidate on layout, build on first read. This also collapses
the a11y build of four resize events into one, because only the last frame is ever
read. It is the same idea as every other lazily-computed tree in a browser.

`Sources/Engine/Core/BrowserTab.swift:66-67`

```diff
-    private(set) var accessibilityTree: AccessibilityNode? = nil
-    var needsAccessibility: Bool = false
+    private var builtAccessibilityTree: AccessibilityNode? = nil
+    /// Set by a layout, cleared by the first reader. During a resize drag four
+    /// layouts in a row used to rebuild the whole tree four times for a reader that
+    /// only ever looks at the last one.
+    var needsAccessibility: Bool = true
+    var accessibilityTree: AccessibilityNode? {
+        guard let rootFrame else { return nil }
+        if needsAccessibility {
+            browser?.measure.start("BrowserTab.a11y")
+            let tree: AccessibilityNode = AccessibilityNode(node: rootFrame.nodes)
+            tree.build()
+            browser?.measure.stop("BrowserTab.a11y")
+            builtAccessibilityTree = tree
+            needsAccessibility = false
+        }
+        return builtAccessibilityTree
+    }
```

`Sources/Engine/Core/BrowserTab.swift:180-187` — delete the eager build block

```diff
-        if needsAccessibility {
-            browser?.measure.start("BrowserTab.a11y")
-            let tree: AccessibilityNode = AccessibilityNode(node: rootFrame.nodes)
-            tree.build()
-            accessibilityTree = tree
-            browser?.measure.stop("BrowserTab.a11y")
-            needsAccessibility = false
-        }
         rootFrame.paint()
```

All five read sites (`Browser.swift:238`, `948`, `958`, `986`, `1055`) are on the main
actor, so building inside the getter is safe. `private(set)` has to go: a computed
property has no setter to restrict.

### Step 8 — (background, next) `contentHash` allocates per display item

`Browser.rasterKey` hashes every display item of every layer, for the previous frame and
the new one, on every composite (`Browser.swift:611-620`). `contentHash`
(`DisplayCommand.swift:11-17`) starts with `String(describing: type(of: self))` and,
for text, `CTFontCopyPostScriptName(cmd.font.ctFont) as String` — two allocations per
item, ~20k per composite on that page. It runs off the main thread, which is why it is
not the stutter, but it is most of `raster.composite` (~30ms per composite, 36
composites, 1.1s) and therefore part of the delay before the new pixels appear.

Fix direction: cache the type-name string per concrete type (or use a small enum), and
hash the `CTFont` identity plus size instead of the PostScript name string.

## Housekeeping

`Browser.animationTick` still has the `print("tick")` probe from the Round 1
verification (`Browser.swift:166`). It is not free — ~1700 line writes per 27s run —
so drop it now that step 1 is confirmed.

## Revised order

| | Change | Expect |
|---|---|---|
| 6 | hoist the transform regex | paint ~122ms → ~60ms |
| 7 | a11y: skip when off (A) or build lazily (B) | a11y ~37ms → ~0 (A) or once per idle frame (B) |
| 5 | real horizontal overflow | reaches `<pre>` and any `overflow: auto` box |
| 3 | incremental layout | layout ~70ms → a fraction |
| 8 | cache `contentHash` parts | composite ~30ms → less background latency |

After 6 and 7 a resize tick should be roughly layout-only (~70ms in debug, ~26ms
release), which is ~13fps in debug during a drag.

---

# Round 3 — steps 6, 7 and 8 measured

Both traces below are real `ToyStack` app runs (debug build) on `visual-effects.html`.

| Span | Round 2 | Round 3 | Δ |
|---|---|---|---|
| `BrowserTab.paint` | 122.7ms (22 calls) | **53.3ms** (17 calls) | **−57%** |
| `BrowserTab.a11y` | 37.2ms (22 calls) | **0 — not built** | −37ms per tick |
| `raster.composite` (real ones) | 49–53ms | **34–36ms** | **−31%** |
| `raster.plan` | ~55ms | 37–39ms | −30% |
| `BrowserTab.layout` | 75.8ms | 71.1ms | unchanged, as expected |
| `BrowserTab.style` | 176ms (4 calls) | 179ms (2 calls) | unchanged when it fires |

A resize tick went from ~235ms of main-thread work (layout 76 + a11y 37 + paint 122)
to ~124ms (layout 71 + paint 53), and the observed gap between ticks went from
240–272ms to 132–160ms — about 7 reflows/second instead of 4.

**Correctness check that matters more than the numbers:** the tile cache still hits.
The `tiles` counter shows `{hits: 110, misses: 0}` on unchanged frames and
`{hits: 96–134, misses: 0–12}` while scrolling, so the new hash still produces equal
values for equal content. A hash that had become unstable would show `hits: 0`
forever. The `raster.composite` aggregate average also dropped 30.34ms → 24.09ms, but
that number mixes in no-op composites; compare the real ones (34–36ms) against the
real ones from Round 2 (49–53ms).

## What is left, and where

Sampling the same long page again (main thread, 1411 samples):

| Branch | Share |
|---|---|
| `Frame.runAnimationFrame` → style/layout | ~49% |
| `Frame.paint()` → `paintTree` | ~34% |
| `Frame.load` → parse | ~14% |

Paint no longer has one dominant line — the leaf samples are now spread across
`malloc`/`swift_retain`/`swift_release`/metadata lookups, i.e. many small allocations
rather than one hotspot. Two of those are still worth naming.

### Step 9 — the same per-node Foundation call, for `border-radius`

`BrowserVisualEffect.swift:37` is now the biggest single item inside paint:

```
64 paintBrowserVisualEffects(node:items:rect:)      BrowserVisualEffect.swift:37
└ 37 StringProtocol.replacingOccurrences(of:with:)  ← 58% of it
  └ 17 -[NSString stringByReplacingOccurrencesOfString:...]
```

It is exactly the shape of the regex bug: an allocating string operation, once per
node, *before* the guard that returns early for the ~99% of nodes that have no
radius. `"0px".replacingOccurrences(of: "px", with: "")` bridges to `NSString` and
builds a mutable string to produce `"0"`.

Micro-benchmark (12k nodes per paint, the same value mix a page actually has):

```
                 debug (-Onone)     release (-O)
replacingOccurrences: 0.78 us/call   0.58 us/call
hasSuffix/dropLast  : 0.33 us/call   0.05 us/call  → ~5ms per paint
```

The four `border-radius` sites all do this, and three of them (`BlockLayout.paint`,
`IframeLayout.paint`, `InputLayout.paint`) are on the paint path too. One parser, four
callers — put it next to `outlineWidth`, which already parses a length the cheap way
(`CSSValueParser.swift:46-55`).

`Sources/Engine/Style/CSSValueParser.swift`

```diff
     static func outlineWidth(_ token: String) -> CGFloat? {
         switch token {
             case "thin": return 1
             case "medium": return 3
             case "thick": return 5
             default:
                 guard token.hasSuffix("px"), let value = Double(token.dropLast(2)) else { return nil }
                 return CGFloat(value)
         }
     }
 
+    /// A plain `Npx` length, for properties that only ever take one
+    /// (`border-radius`). 0 for anything else, including the multi-value form
+    /// `4px 8px`, which this engine does not support yet.
+    static func px(_ css: String?) -> CGFloat {
+        guard let css, css.hasSuffix("px"), let value = Double(css.dropLast(2)) else { return 0 }
+        return CGFloat(value)
+    }
+
     static func backgroundImageURL(_ value: String) -> String? {
```

`Sources/Engine/Display/BrowserVisualEffect.swift:37-38`

```diff
     let translation: CGPoint? = CSSValueParser.transform(node.style["transform"] ?? "")
-    let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")
-    let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
+    let borderRadius: CGFloat = CSSValueParser.px(node.style["border-radius"])
     let blurRadius: CGFloat = CSSValueParser.blur(node.style["filter"] ?? "")
```

`Sources/Engine/Layouts/BlockLayout.swift:434-436`, `IframeLayout.swift:55-56`,
`InputLayout.swift:67-68` — the same two lines, three times, with
`node.style` / `element.style` respectively:

```diff
     let bgcolor: String = node.style["background-color"] ?? "transparent"
-    let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(
-        of: "px", with: "")
-    let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
+    let borderRadius: CGFloat = CSSValueParser.px(node.style["border-radius"])
```

Behaviour is identical for every input the parser can produce — `nil`/`0px`/`4px`/`8px`
give the same number, and `50%` / `4px 8px` give 0 both ways, which is why the
multi-value limitation is worth a comment rather than a silent difference.

### Step 10 — `inPaintOrder` sorts children that are already in order

`PaintTree.swift:51-62` runs for **every** object with children and does
`.enumerated().sorted { ... }.map { $0.element }` — three array allocations per node,
with a comparator that reads `node.style["position"]` and `node.style["z-index"]` per
comparison. `effectiveZIndex` returns 0 for every static element, so on a page with no
`position`/`z-index` at all this is pure overhead. In the sample it is the second
biggest paint item (`Sequence.sorted(by:)` + `MutableCollection<>.sort(by:)` +
the closure).

```diff
 @MainActor
 func inPaintOrder(_ children: [any LayoutObject]) -> [any LayoutObject] {
+    // Nothing is positioned: the sort would be a no-op, and it costs three array
+    // copies per node. This is the common case on every page in `www/`.
+    guard children.contains(where: { ($0.node.style["position"] ?? "static") != "static" })
+    else { return children }
     return children.enumerated()
         .sorted { a, b in
             let za: Int = effectiveZIndex(a.element.node)
             let zb: Int = effectiveZIndex(b.element.node)
             return za == zb ? a.offset < b.offset : za < zb
         }
         .map { $0.element }
 }
```

The remaining paint cost is the display list itself: `paintTree` appends every
subtree's items into a fresh array at every level (`PaintTree.swift:16-39`), so a
12k-item list is copied once per level of depth. That is a real design change
(build one flat list, or pass `inout` through) rather than a line edit, and it is
worth its own plan together with step 3.

## Order from here

→ The open items (incremental layout, incremental paint, the remaining small wins,
and the horizontal-overflow work) are tracked in
[`resize-reflow-remaining-work.md`](./resize-reflow-remaining-work.md).

| | Change | Expect |
|---|---|---|
| 9 | parse `border-radius` instead of replacing in it | paint ~53ms → ~48ms |
| 3 | incremental layout | layout 71ms → a fraction (the biggest item left) |
| 10 | skip the sort when nothing is positioned | a slice of the remaining paint |
| 5 | real horizontal overflow | reaches `<pre>` and any `overflow: auto` box |

## One thing to make explicit in step 7

The a11y gate `if needsAccessibility, browser?.accessibilityIsOn == true`
(`BrowserTab.swift:180`) only builds after `Ctrl+A` **because** the flag is never
cleared while a11y is off: `Frame.render()` sets it on every layout, and the gate
leaves it set. It works, but it depends on that. Add `activeTab?.needsAccessibility = true`
to `Browser.toggleAccessibility()` (`Browser.swift:1046`) so turning a11y on does not
rely on a side effect.
