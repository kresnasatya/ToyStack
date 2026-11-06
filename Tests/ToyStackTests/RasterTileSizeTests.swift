import CoreGraphics
import Testing

@testable import Engine

@Suite
struct RasterTileSizeTests {
    @Test func wideLayerUsesAtMostTwentyFourTiles() {
        let bounds: Rect = Rect(left: 0, top: 0, right: 1000, bottom: 700)
        let item: DisplayOp = .rect(rect: bounds, color: BrowserColor(cssName: "black"))
        var layer: RasterLayer = RasterLayer(items: [item], bounds: bounds)
        let region: RasterRegion = RasterRegion(hint: bounds, visible: bounds)
        let store: TileStore = TileStore(tileSize: RasterLayer.tileSize)
        let strips: [TileStrip] = layer.rasterIfNeeded(
            index: 0,
            scale: 1,
            store: store,
            region: region,
            budget: RasterBudget(1_000)
        )
        let tiles: Int = strips.reduce(0) { $0 + $1.tiles.count }
        #expect(tiles <= 24, "layer split into \(tiles) tiles")
    }
}
