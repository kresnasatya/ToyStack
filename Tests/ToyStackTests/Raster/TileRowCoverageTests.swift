import CoreGraphics
import Testing

@testable import Engine

@Suite
struct TileRowCoverageTests {
    private let grid: TileGrid = TileGrid(scale: ContentScale(display: 2))

    private func rect(top: CGFloat, bottom: CGFloat, right: CGFloat = 256, color: String = "black") -> DisplayOp {
        return .rect(rect: Rect(left: 0, top: top, right: right, bottom: bottom), color: BrowserColor(cssName: color))
    }

    private func layer(_ items: [DisplayOp]) -> RasterLayer {
        var layer: RasterLayer = RasterLayer(displayItem: items[0])
        for item in items.dropFirst() { layer.add(item) }
        return layer
    }

    private func raster(_ layer: inout RasterLayer) -> [TileIndex: CGImage] {
        let everything: Rect = Rect(left: 0, top: 0, right: 1024, bottom: 1024)
        let strips: [TileStrip] = layer.rasterIfNeeded(
            index: 0,
            grid: grid,
            store: TileStore(tileSize: RasterLayer.tileSize),
            region: RasterRegion(hint: everything, visible: everything),
            budget: RasterBudget(RasterLayer.rasterCapPerComposite)
        )
        var tiles: [TileIndex: CGImage] = [:]
        let target: RasterTarget = RasterTarget(scale: grid.scale.effective)
        for strip in strips {
            guard let image: CGImage = TileStripRasterizer.render(strip, target: target) else { continue }
            for key in strip.tiles {
                tiles[key.index] = image.cropping(to: TileStrip.sliceRect(for: key, in: strip.bounds, grid: grid))
            }
        }
        return tiles
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let context: CGContext = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return pixel[3]
    }

    @Test func itemEndingJustPastARowBoundaryReachesTheNextRow() throws {
        var layer: RasterLayer = layer([rect(top: 0, bottom: 128.5)])
        let tiles: [TileIndex: CGImage] = raster(&layer)
        let below: CGImage = try #require(tiles[TileIndex(row: 1, col: 0)])
        #expect(alpha(of: below, x: 10, y: 0) == 255)
    }

    @Test func hairlineJustBelowARowBoundaryIsDrawn() throws {
        var layer: RasterLayer = layer([rect(top: 128.2, bottom: 128.8), rect(top: 300, bottom: 400)])
        let tiles: [TileIndex: CGImage] = raster(&layer)
        let below: CGImage = try #require(tiles[TileIndex(row: 1, col: 0)])
        #expect(alpha(of: below, x: 10, y: 0) > 0)
    }

    @Test func layerEndingJustPastATileStillGetsTheNextRowAndColumn() throws {
        var layer: RasterLayer = layer([rect(top: 0, bottom: 128.5, right: 128.5)])
        let tiles: [TileIndex: CGImage] = raster(&layer)
        let below: CGImage = try #require(tiles[TileIndex(row: 1, col: 0)])
        let beside: CGImage = try #require(tiles[TileIndex(row: 0, col: 1)])
        #expect(alpha(of: below, x: 10, y: 0) == 255)
        #expect(alpha(of: beside, x: 0, y: 10) == 255)
    }

    @Test func itemEndingExactlyOnARowBoundaryStaysOutOfTheNextRow() throws {
        var layer: RasterLayer = layer([rect(top: 0, bottom: 128), rect(top: 300, bottom: 400, color: "red")])
        let tiles: [TileIndex: CGImage] = raster(&layer)
        let below: CGImage = try #require(tiles[TileIndex(row: 1, col: 0)])
        #expect(alpha(of: below, x: 10, y: 0) == 0)
    }

    @Test func recoloringTheOverhangInvalidatesTheNextRow() {
        var black: RasterLayer = layer([rect(top: 0, bottom: 128.5), rect(top: 300, bottom: 400)])
        var red: RasterLayer = layer([rect(top: 0, bottom: 128.5, color: "red"), rect(top: 300, bottom: 400)])
        _ = raster(&black)
        _ = raster(&red)
        let row1: TileIndex = TileIndex(row: 1, col: 0)
        #expect(black.content.tileCache.keys[row1] != red.content.tileCache.keys[row1])
    }
}
