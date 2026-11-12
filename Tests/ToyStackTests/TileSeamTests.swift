import CoreGraphics
import Testing

@testable import Engine

@Suite
struct TileSeamTests {
    private static let zoomSteps: [CGFloat] = [1.1, 1 / 1.1, 1.1 * 1.1 * 1.1 * 1.1 * 1.1]

    private func placements(at scale: ContentScale) -> [LayerPlacement] {
        let bounds: Rect = Rect(left: 0, top: 0, right: 512, bottom: 512)
        var layer: RasterLayer = RasterLayer(
            displayItem: .rect(rect: bounds, color: BrowserColor(cssName: "black"))
        )
        let strips: [TileStrip] = layer.rasterIfNeeded(index: 0, grid: TileGrid(scale: scale), store: TileStore(tileSize: RasterLayer.tileSize), region: RasterRegion(hint: bounds, visible: bounds), budget: RasterBudget(RasterLayer.rasterCapPerComposite))
        let target: RasterTarget = RasterTarget(scale: scale.effective)
        for strip in strips {
            guard let image: CGImage = TileStripRasterizer.render(strip, target: target) else { continue }
            for key in strip.tiles {
                let slice: CGRect = TileStrip.sliceRect(for: key, in: strip.bounds, grid: TileGrid(scale: scale))
                layer.tiles[key.index] = image.cropping(to: slice)
            }
        }
        return RasterDrawList.placements([layer], effectStrategies: [LayerEffectStrategy(kind: .flat, effect: nil, blur: 0)])
    }

    @Test(arguments: zoomSteps)
    func tileImageFillsItsLayerPixelForPixel(page: CGFloat) throws {
        let scale: ContentScale = ContentScale(display: 2, page: page)
        let placed: [LayerPlacement] = placements(at: scale)
        try #require(placed.count > 1)
        for tile in placed {
            #expect(abs(tile.frame.width * scale.effective - CGFloat(tile.image.width)) < 1e-6)
            #expect(abs(tile.frame.height * scale.effective - CGFloat(tile.image.height)) < 1e-6)
        }
    }

    @Test(arguments: zoomSteps)
    func tileEdgesLandOnWholeDevicePixels(page: CGFloat) throws {
        let scale: ContentScale = ContentScale(display: 2, page: page)
        let placed: [LayerPlacement] = placements(at: scale)
        try #require(placed.count > 1)
        for tile in placed {
            for edge: CGFloat in [tile.frame.minX, tile.frame.maxX, tile.frame.minY, tile.frame.maxY] {
                let pixel: CGFloat = edge * scale.effective
                #expect(abs(pixel - pixel.rounded()) < 1e-6)
            }
        }
    }
}
