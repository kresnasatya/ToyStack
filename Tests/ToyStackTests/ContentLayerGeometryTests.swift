import CoreGraphics
import Testing

@testable import Engine

@Suite
struct ContentLayerGeometryTests {
    private let view: CGSize = CGSize(width: 1440, height: 703)
    private let smallerView: CGSize = CGSize(width: 1300, height: 703)

    private func shownState(page: CGFloat) -> ContentPresentationState {
        var state = ContentPresentationState()
        state.didShow(layoutSize: view, viewSize: view, page: page)
        return state
    }

    @Test func boundLayersUseTheFrameZoomAndScroll() {
        let frameScale: ContentScale = ContentScale(display: 2, page: 1.1)
        let offset: ContentOffset = ContentOffset(top: 80, scroll: 100 * 1.1)

        let geometry: ContentLayerGeometry = ContentLayerGeometry(
            offset: offset,
            frameScale: frameScale,
            layerPage: 1.1,
            previewScale: 1
        )

        #expect(geometry.scale == 1.1)
        #expect(geometry.originY == -30)
    }

    @Test func olderLayersScrollAtTheirOwnZoom() {
        let frameScale: ContentScale = ContentScale(display: 2, page: 1.1)
        let offset: ContentOffset = ContentOffset(top: 80, scroll: 100 * 1.1)
        let page: CGFloat = shownState(page: 1).layerPage(framePage: 1.1, showsOlderLayers: true)

        let geometry: ContentLayerGeometry = ContentLayerGeometry(
            offset: offset,
            frameScale: frameScale,
            layerPage: page,
            previewScale: 1
        )

        #expect(geometry.scale == 1)
        #expect(geometry.originY == -20)
    }

    @Test(arguments: [(shown: 1.0, frame: 1.1), (shown: 1.1, frame: 1.1 * 1.1), (shown: 1.1, frame: 1.0)])
    func previewOfOlderZoomKeepsTilesOnDevicePixels(zoom: (shown: CGFloat, frame: CGFloat)) {
        let frameScale: ContentScale = ContentScale(display: 2, page: zoom.frame)
        let fit: PreviewFit = PreviewFit(old: view, new: smallerView, scale: frameScale)
        let page: CGFloat = shownState(page: zoom.shown).layerPage(framePage: zoom.frame, showsOlderLayers: true)

        let geometry: ContentLayerGeometry = ContentLayerGeometry(
            offset: ContentOffset(top: 80, scroll: 0),
            frameScale: frameScale,
            layerPage: page,
            previewScale: fit.scale
        )
        let shownTile: CGFloat = TileGrid(scale: ContentScale(display: 2, page: zoom.shown)).size
        let tilePixels: CGFloat = shownTile * geometry.scale * 2

        #expect(abs(tilePixels - tilePixels.rounded()) < 1e-9)
    }

    @Test func previewOfOlderZoomScrollsWithTheShrunkLayers() {
        let frameScale: ContentScale = ContentScale(display: 2, page: 1.1)
        let fit: PreviewFit = PreviewFit(old: view, new: smallerView, scale: frameScale)
        let page: CGFloat = shownState(page: 1).layerPage(framePage: 1.1, showsOlderLayers: true)

        let geometry: ContentLayerGeometry = ContentLayerGeometry(
            offset: ContentOffset(top: 80, scroll: 100 * 1.1),
            frameScale: frameScale,
            layerPage: page,
            previewScale: fit.scale
        )
        let expected: CGFloat = ((80 - 100 * fit.scale) * 2).rounded() / 2

        #expect(abs(geometry.originY - expected) < 1e-9)
    }
}
