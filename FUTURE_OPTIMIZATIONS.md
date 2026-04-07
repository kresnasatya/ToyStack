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
