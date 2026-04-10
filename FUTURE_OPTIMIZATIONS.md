## Future Optimizations

### Layer Rasterization Cache (Level 3 Compositing)

Currently SwiftUI's `Canvas` re-executes all paint commands in `drawList`
on every scroll event. There is no off-screen bitmap cache — every Canvas
refresh re-encodes all draw commands into Metal from scratch.

Python's reference implementation (`brownie`) avoids this using Skia
`Surface` objects. Each `CompositedLayer` holds a pre-rasterized off-screen
GPU bitmap. On scroll, Python only blits existing bitmaps without
re-encoding any paint commands. Layout changes invalidate and re-raster
only the affected layers.

The three levels of rendering optimization and where ToyStack currently stands:

| Level | Description | brownie | ToyStack |
|-------|-------------|---------|----------|
| 1 | Skip work on idle frames | timer only fires on demand | `needsAnimationFrame` guard |
| 2 | Skip `composite()` on scroll/animation | `needs_composite` flag | `needsComposite` flag |
| 3 | Reuse rasterized bitmaps, blit on scroll | Skia `Surface` per layer | not implemented |

Three implementation options were evaluated for Level 3:

#### Option A — Stay with SwiftUI `Canvas` (current, chosen)
- CPU cost: high per scroll (re-encodes all paint commands to Metal each frame)
- RAM: low (only paint command structs in memory)
- **Decision: keep this approach.** For a learning project, low RAM and low
  complexity outweigh the CPU cost. The bottleneck only manifests on pages
  with hundreds of paint commands and fast continuous scrolling.

#### Option B — `CGImage` cache per `CompositedLayer`
- Rasterize each layer once into a `CGImage`; blit on scroll
- CPU cost: low per scroll
- RAM: medium to high — each layer costs `width × height × 4 bytes` (RGBA).
  A full-page layer (800×3000) is ~9 MB. Large pages with few compositing
  effects could produce one giant layer → hundreds of MB.
- Risk: must cap or split oversized layers before caching
- Implementation: moderate — fill the `rasterTab()` stub in `Browser.swift`,
  add `cachedImage`/`isDirty` fields to `CompositedLayer`, change
  `DrawCompositedLayer.execute()` to blit instead of re-raster

#### Option C — Metal textures per `CompositedLayer`
- Rasterize each layer into a GPU-resident `MTLTexture`; blit entirely on GPU
- CPU cost: very low per scroll (no CPU→GPU copy)
- VRAM: medium to high (same size math as Option B, but in VRAM)
- **Apple Silicon note:** on M-series Macs, RAM and VRAM are unified memory,
  so the CPU→GPU copy in Option B is already cheap. The practical gap between
  B and C narrows significantly on this hardware.
- Implementation: very high — replace `Canvas` with `MTKView`, rewrite all
  `PaintCommand.execute()` methods with a parallel `CGContext` draw path,
  implement a Metal render pipeline, manage `MTLCommandQueue` and
  `MTLCommandBuffer`. Touches nearly every file in the engine.
- Suitable as a separate project if the goal is learning Metal specifically.

### Incremental Layout for Overflow Scroll Containers

**Context:** `exercise-12-1.html` appends divs to a `#log` element (`overflow-y: scroll`) via `setInterval`. As the child count grows, `setNeedsRender()` triggers a full pipeline every frame:
- `applyStyle` — walks entire DOM tree
- `DocumentLayout` — lays out all children including all appended divs
- `paintTree` — generates paint commands (mitigated by paint culling)

Layout cost is O(n) and grows unboundedly. At ~200 children, per-frame layout time exceeds one frame budget (16ms), causing a backlog on the main thread. Clicking "Stop" feels delayed because the click event queues behind already-scheduled renders.

**What real browsers do:** Overflow scroll containers are isolated layout contexts. Appending a child only re-lays that subtree, not the whole document. The compositor handles scroll offset cheaply without re-layout.

**Proposed fix:** When a DOM mutation targets a node inside an `overflow: scroll` container, skip the full `DocumentLayout` pass and only re-layout that subtree. Requires:
1. Tracking which `BlockLayout` owns a mutated node
2. Re-running layout only from that block downward
3. Patching `y` positions of siblings below the insertion point

**Affected files:** `Tab.swift` (`render()`), `Layouts/BlockLayout.swift`, `JSRuntime.swift` (mutation bindings).

### True Animation/Raster Parallelism (Exercise 12-3 follow-up)

**Context:** Exercise 12-3 splits the frame pipeline into two phases — animation frame (JS + style/layout) on the main thread, and composite/raster/draw enqueued as a separate `Task { @MainActor in }`. The intent is for both threads to do work simultaneously.

**Observed behavior:** The output logs show strictly sequential execution — `[frame] animation END` always precedes `[raster] START`. No true overlap occurs.

**Why:** Both `animationTick` and the raster `Task { @MainActor in }` are bound to `@MainActor`. Swift's cooperative scheduler drains all enqueued `@MainActor` tasks before yielding back to the run loop, so the raster Task completes before the next timer tick fires `animationTick`. Cooperative threading, not parallelism.

**What absolute-time scheduling does achieve (confirmed):** After a slow frame (e.g. 36ms on browser.engineering), the scheduler snaps back to ~16.7ms cadence on the next tick — proving the absolute-time target logic works correctly.

**To get true overlap:** Extract raster state out of `@MainActor` into a separate actor:

```swift
actor RasterThread {
    func compositeRasterAndDraw(...) { ... }
}
```

Then in `commit()`, call `Task.detached { await rasterThread.compositeRasterAndDraw(...) }`. This runs on a real background thread, genuinely concurrent with the next animation frame on main. Requires extracting `compositedLayers`, `drawList`, and related state from `Browser` into the new actor, and posting `objectWillChange.send()` back to `@MainActor` after raster completes.

**Affected files:** `Browser.swift` (extract raster state + `compositeRasterAndDraw`), `ToyStack.swift` (BrowserView must read draw list via `@MainActor`).
