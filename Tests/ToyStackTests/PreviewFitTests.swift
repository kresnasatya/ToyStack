import CoreGraphics
import Testing

@testable import Engine

@Suite
struct PreviewFitTests {
    @Test func fitsWideContentIntoNarrowViewport() {
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1000, height: 700),
            new: CGSize(width: 800, height: 700)
        )
        #expect(abs(fit.scale - 0.8) < 0.0001)
        #expect(abs(fit.scaledSize.width - 800) < 0.0001)
        #expect(abs(fit.scaledSize.height - 560) < 0.0001)
    }

    @Test func doesNotStretchWhenHeightHasRoom() {
        let fit: PreviewFit = PreviewFit(
            old: CGSize(width: 1000, height: 700),
            new: CGSize(width: 1000, height: 900)
        )
        #expect(fit.scale == 1)
        #expect(fit.scaledSize == CGSize(width: 1000, height: 700))
    }

    @Test func ignoresInvalidPreviousSize() {
        let fit: PreviewFit = PreviewFit(
            old: .zero,
            new: CGSize(width: 800, height: 700)
        )
        #expect(fit.scale == 1)
    }
}
