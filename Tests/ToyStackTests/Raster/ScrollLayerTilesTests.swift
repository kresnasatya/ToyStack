import CoreGraphics
import Testing

@testable import Engine

@Suite
@MainActor
struct ScrollLayerTilesTests {
    private static let scrollport: Rect = Rect(left: 0, top: 0, right: 100, bottom: 100)
    private static let red: BrowserColor = BrowserColor(cssName: "red")
    private static let blue: BrowserColor = BrowserColor(cssName: "blue")

    @Test func contentInsideAScrollBoxStaysOnTiles() {
        let ops: [DisplayOp] = Self.scrollBox(offset: 0, content: [
            .rect(rect: Rect(left: 0, top: 0, right: 100, bottom: 50), color: Self.red),
        ])

        let strategies: [LayerEffectStrategy] = Self.strategies(ops)

        #expect(strategies.map(\.kind) == [.flat])
    }

    @Test func translucentContentInsideAScrollBoxStillFallsBack() {
        let blend: EffectScope = Self.scope(.blend(opacity: 0.5, mode: nil), ordinal: 1)
        let ops: [DisplayOp] = Self.scrollBox(offset: 0, content: [
            .beginEffect(blend),
            .rect(rect: Rect(left: 0, top: 0, right: 100, bottom: 50), color: Self.red),
            .endEffect,
        ])

        let strategies: [LayerEffectStrategy] = Self.strategies(ops)

        #expect(strategies.map(\.kind) == [.scrollFallback])
    }

    @Test func scrolledContentMovesUpByTheScrollOffset() {
        let ops: [DisplayOp] = Self.scrollBox(offset: 50, content: [
            .rect(rect: Rect(left: 0, top: 60, right: 100, bottom: 70), color: Self.red),
        ])

        let pixels: PagePixels = Self.tilePixels(ops)

        #expect(pixels.matches(Self.red, x: 50, y: 15))
        #expect(pixels.isClear(x: 50, y: 65))
    }

    @Test func contentScrolledOutOfTheBoxIsClipped() {
        let ops: [DisplayOp] = Self.scrollBox(offset: 20, content: [
            .rect(rect: Rect(left: 0, top: 0, right: 100, bottom: 200), color: Self.blue),
        ])

        let pixels: PagePixels = Self.tilePixels(ops)

        #expect(pixels.matches(Self.blue, x: 50, y: 5))
        #expect(pixels.matches(Self.blue, x: 50, y: 95))
        #expect(pixels.isClear(x: 50, y: 105))
        #expect(pixels.isClear(x: 50, y: 170))
    }

    @Test func scrollingTheBoxChangesTheTileKeys() {
        let content: [DisplayOp] = [
            .rect(rect: Rect(left: 0, top: 60, right: 100, bottom: 70), color: Self.red),
        ]

        let resting: Set<TileKey> = Self.tileKeys(Self.scrollBox(offset: 0, content: content))
        let scrolled: Set<TileKey> = Self.tileKeys(Self.scrollBox(offset: 30, content: content))

        #expect(resting.isDisjoint(with: scrolled))
    }

    // MARK: - Helpers

    private static func scope(_ kind: EffectKind, ordinal: Int) -> EffectScope {
        return EffectScope(
            id: EffectScopeID(paint: 1, ordinal: ordinal),
            kind: kind,
            placement: EffectPlacement(rect: scrollport, node: nil, animatedTransform: false)
        )
    }

    private static func scrollBox(offset: CGFloat, content: [DisplayOp]) -> [DisplayOp] {
        let scroll: EffectScope = scope(
            .scroll(ClipShape(rect: scrollport, radii: .zero), offset: offset),
            ordinal: 0
        )
        return [.beginEffect(scroll)] + content + [.endEffect]
    }

    private static func input(_ ops: [DisplayOp]) -> RasterInput {
        return RasterInput(
            scene: RasterScene(displayList: ops, compositedUpdates: [:], previousLayers: []),
            settings: RasterSettings(
                viewport: Viewport(
                    windowSize: CGSize(width: 256, height: 256),
                    scale: ContentScale(display: 1, page: 1),
                    colorSpace: RasterTarget.sRGB
                ),
                colors: PageColors(preferences: ColorPreferences(prefersDark: false, usesForcedColors: false), canvasBackground: nil),
                flags: RasterInvalidation(needsComposite: true, needsDraw: true),
                accessibility: AccessibilityBounds(hoveredBounds: nil, readBounds: nil)
            ),
            scrollState: ScrollState(scroll: 0, interestTop: 0, interestBottom: 0, maxScroll: 0)
        )
    }

    private static func layers(_ ops: [DisplayOp]) -> [RasterLayer] {
        return RasterCompositor.compute(input(ops), measure: MeasureTime(), frame: 0)
    }

    private static func strategies(_ ops: [DisplayOp]) -> [LayerEffectStrategy] {
        return layers(ops).map { LayerEffectStrategy.resolve($0, updates: [:]) }
    }

    private static func strips(_ ops: [DisplayOp]) -> [TileStrip] {
        let grid: TileGrid = TileGrid(scale: ContentScale(display: 1))
        let everything: Rect = Rect(left: 0, top: 0, right: 256, bottom: 256)
        var strips: [TileStrip] = []
        for (index, var layer) in layers(ops).enumerated() {
            strips += layer.rasterIfNeeded(
                index: index,
                grid: grid,
                store: TileStore(tileSize: RasterLayer.tileSize),
                region: RasterRegion(hint: everything, visible: everything),
                budget: RasterBudget(RasterLayer.rasterCapPerComposite)
            )
        }
        return strips
    }

    private static func tileKeys(_ ops: [DisplayOp]) -> Set<TileKey> {
        return Set(strips(ops).flatMap(\.tiles))
    }

    private static func tilePixels(_ ops: [DisplayOp]) -> PagePixels {
        let grid: TileGrid = TileGrid(scale: ContentScale(display: 1))
        let target: RasterTarget = RasterTarget(scale: 1)
        var placed: [DisplayOp] = []
        for strip in strips(ops) {
            guard let image: CGImage = TileStripRasterizer.render(strip, target: target) else { continue }
            for key in strip.tiles {
                guard let tile: CGImage = image.cropping(
                    to: TileStrip.sliceRect(for: key, in: strip.bounds, grid: grid)
                ) else { continue }
                let frame: CGRect = grid.frame(for: key.index)
                placed.append(.image(
                    image: tile,
                    rendering: .auto,
                    rect: Rect(left: frame.minX, top: frame.minY, right: frame.maxX, bottom: frame.maxY),
                    version: 0
                ))
            }
        }
        return PagePixels(placed, width: 256, height: 256)
    }
}
