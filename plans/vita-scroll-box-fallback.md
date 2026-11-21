# Why the VITA page scrolled at 5 fps

## What the trace showed

`browser.trace` (GUI, 1438×698 window, about 44 s, 1223 scroll events):

| Span | Count | Average | Max |
|---|---|---|---|
| `raster.bitmap` (compositor) | 180 | 162 ms | 212 ms |
| `raster.install` (compositor) | 457 | 65 ms | 212 ms |
| `BrowserTab.paint` (main) | 1915 | 0.8 ms | 4.1 ms |
| `BrowserTab.style` (main) | 64 | 1.1 ms | 5.8 ms |

The main thread was fine. Almost every composite after the page loaded went
through `raster.bitmap`, which redraws the whole display list on the CPU, so
the compositor could only deliver about 5 frames per second. The `tiles`
counter, which is emitted only on the tiled path, appeared just 3 times after load.

## Why

`LayerEffectStrategy.resolve` (`Sources/Engine/Raster/LayerEffectStrategy.swift`)
marked every layer inside an `overflow: scroll` box as `.scrollFallback`. A
single such layer turns off tiles and Core Animation sublayers for the whole
page (`Sources/Engine/Core/Browser.swift:527`), so the compositor falls back to
`CGRenderer.renderBitmap` over the full draw list. That path does not cull
anything outside the viewport, and every opacity or blur scope becomes a
transparency layer.

Each example on its own was fine:

- `ch11/exercise-11-3.html` has a scroll box but nothing that animates, so the
  slow path ran once.
- The chapter 13 pages animate but have no scroll box, so they used tiles plus
  Core Animation.

The VITA page has both: two scroll boxes (the scrollable box and the
`setInterval` log) plus animations that never stop (keyframes, transitions
driven by `setTimeout`). Every animation frame paid for a full CPU redraw.

The same page in ToyStackHeadless (release build, 240 frames, 60 scroll events)
confirmed this:

| Variant | `raster.install` average |
|---|---|
| VITA as is | 156 ms |
| VITA without `filter: blur` | 122 ms |
| VITA without the two scroll boxes | 3.4 ms |

## Fix

Plain content inside a scroll box now goes on tiles like the rest of the page:

- `LayerScroll` (`Sources/Engine/Raster/LayerScroll.swift`) collects the
  scrollport clips and the total scroll offset from a layer's ancestor scopes.
  `RasterCompositor` stores it in `LayerContent.scroll`.
- `RasterLayer.rasterIfNeeded` shifts the items by that offset, limits the
  layer bounds to the scrollport, and includes the clips in the tile hash.
- `TileStrip` carries the clips in `TileStripContent`, and
  `TileStripRasterizer` applies them before drawing.
- `LayerEffectStrategy` still falls back when a layer inside a scroll box also
  needs a Core Animation effect (opacity, transform, blur), because effect
  images are not shifted or clipped.
- In the bitmap path, `executeCompositedLayer` ignores the tiles of a scroll
  layer, because they already include the offset and clip that the enclosing
  scroll effect would apply a second time.

Result for the same headless run: `raster.install` averages 2.7 ms (95th
percentile 3.4 ms), down from 156 ms. Pixels match the old bitmap output within
1/255.

Tests: `Tests/ToyStackTests/Raster/ScrollLayerTilesTests.swift`.
