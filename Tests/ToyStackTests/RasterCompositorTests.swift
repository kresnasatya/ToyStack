import CoreGraphics
import Testing

@testable import Engine

@Suite
@MainActor
struct RasterCompositorTests {
    @Test func opsMergeByEffectScopeAndKeepCommandOrder() {
        let scope: EffectScope = EffectScope(
            id: EffectScopeID(paint: 1, ordinal: 0),
            kind: .blend(opacity: 0.5, mode: nil),
            placement: EffectPlacement(
                rect: Rect(left: 0, top: 0, right: 100, bottom: 100),
                node: nil,
                animatedTransform: false
            )
        )
        let ops: [DisplayOp] = [
            .rect(rect: Rect(left: 0, top: 0, right: 10, bottom: 10), color: BrowserColor(cssName: "black")),
            .beginEffect(scope),
            .rect(rect: Rect(left: 0, top: 0, right: 20, bottom: 20), color: BrowserColor(cssName: "red")),
            .rect(rect: Rect(left: 0, top: 0, right: 30, bottom: 30), color: BrowserColor(cssName: "blue")),
            .endEffect,
            .rect(rect: Rect(left: 0, top: 0, right: 40, bottom: 40), color: BrowserColor(cssName: "green")),
        ]

        let inputs: RasterInput = RasterInput(
            scene: RasterScene(displayList: ops, compositedUpdates: [:], previousLayers: []),
            settings: RasterSettings(
                viewport: Viewport(
                    windowSize: CGSize(width: 800, height: 600),
                    topInset: 0,
                    scale: ContentScale(display: 1, page: 1)
                ),
                preferences: ColorPreferences(prefersDark: false, usesForcedColors: false),
                flags: RasterInvalidation(needsComposite: true, needsDraw: true),
                accessibility: AccessibilityBounds(hoveredBounds: nil, readBounds: nil)
            ),
            scrollState: ScrollState(scroll: 0, interestTop: 0, interestBottom: 0, maxScroll: 0)
        )

        let layers: [RasterLayer] = RasterCompositor.compute(inputs, measure: MeasureTime(), frame: 0)

        #expect(layers.count == 2)
        #expect(layers[0].identity.id == LayerID(effect: nil, ordinal: 0))
        #expect(layers[0].identity.firstCommandIndex == 0)
        #expect(layers[0].content.items.count == 2)

        #expect(layers[1].identity.id == LayerID(effect: scope.id, ordinal: 0))
        #expect(layers[1].identity.firstCommandIndex == 1)
        #expect(layers[1].content.items.count == 2)
        #expect(layers[1].identity.ancestorChain.count == 1)

        let drawList: [DisplayOp] = RasterDrawList.compute(layers: layers, inputs: inputs)
        #expect(drawList.count == 4)
        if case .compositedLayer = drawList[0] {} else { Issue.record("expected first layer") }
        if case .beginEffect = drawList[1] {} else { Issue.record("expected begin effect") }
        if case .compositedLayer = drawList[2] {} else { Issue.record("expected scoped layer") }
        if case .endEffect = drawList[3] {} else { Issue.record("expected end effect") }
    }
}
