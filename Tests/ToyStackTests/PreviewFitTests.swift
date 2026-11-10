import CoreGraphics
import Testing

@testable import Engine

@Suite
struct PreviewFitTests {
    private let retina: ContentScale = ContentScale(display: 2)

    @Test func fitsWideContentIntoNarrowViewport() {
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1024, height: 700),
            new: CGSize(width: 768, height: 700),
            scale: retina
        )
        #expect(abs(fit.scale - 0.75) < 0.0001)
        #expect(abs(fit.scaledSize.width - 768) < 0.0001)
        #expect(abs(fit.scaledSize.height - 525) < 0.0001)
    }

    @Test func doesNotStretchWhenHeightHasRoom() {
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1000, height: 700),
            new: CGSize(width: 1000, height: 900),
            scale: retina
        )
        #expect(fit.scale == 1)
        #expect(fit.scaledSize == CGSize(width: 1000, height: 700))
    }

    @Test func doesNotMagnifyWhenViewportGrows() {
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1000, height: 700),
            new: CGSize(width: 1600, height: 1000),
            scale: retina
        )
        #expect(fit.scale == 1)
        #expect(fit.scaledSize == CGSize(width: 1000, height: 700))
    }

    @Test func ignoresInvalidPreviousSize() {
        let fit: PreviewFit = PreviewFit(
            old: .zero,
            new: CGSize(width: 800, height: 700),
            scale: retina
        )
        #expect(fit.scale == 1)
    }

    @Test func previewTileCoversWholeDevicePixels() {
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1000, height: 700),
            new: CGSize(width: 975, height: 700),
            scale: retina
        )
        let tilePixels: CGFloat = RasterLayer.tileSize * retina.effective * fit.scale

        #expect(tilePixels == tilePixels.rounded())
        #expect(fit.scale <= 0.975)
        #expect(fit.scale > 0.975 - 1.0 / 256.0)
    }

    @Test func zoomedPreviewTileCoversWholeDevicePixels() {
        let zoomed: ContentScale = ContentScale(display: 2, page: 1.25)
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1000, height: 700),
            new: CGSize(width: 970, height: 700),
            scale: zoomed
        )
        let tilePixels: CGFloat = RasterLayer.tileSize * zoomed.effective * fit.scale

        #expect(abs(tilePixels - tilePixels.rounded()) < 1e-9)
        #expect(fit.scale <= 0.97)
    }

    @Test func tinyWindowStillShowsTheContent() {
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1000, height: 700),
            new: CGSize(width: 1, height: 700),
            scale: retina
        )
        #expect(fit.scale > 0)
    }
}
