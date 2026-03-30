# ToyStack

A toy browser engine with Swift. Motivated from [Browser Engineering book](https://browser.engineering).

## NOTE

To run the `right-to-left` text mode, use this command below.

```sh
swift run ToyStack -- --rtl
```

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

To achieve Level 3 in Swift, each `CompositedLayer` would need to cache
its rendered output as a `CGImage` or Metal texture, redraw to it only
when the layer's content changes (DOM mutation, not scroll), and blit the
cached texture on scroll. This is essentially reimplementing what Skia
does, which requires bypassing SwiftUI's `Canvas` and managing GPU
resources manually via Core Graphics or Metal directly.
