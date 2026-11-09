import CoreGraphics
import Testing

@testable import Engine

@Suite
struct PresentedFrameTests {

    @Test func displayedLayoutSizeIncludesPageZoom() {
        let frame: PresentedFrame = PresentedFrame(
            content: RenderedContent(
                source: RenderedSource(layoutSize: CGSize(width: 500, height: 300))
            ),
            viewport: PresentedViewport(
                contentOffset: ContentOffset(top: 0, scroll: 0),
                scale: ContentScale(display: 2, page: 2),
                canvasColor: CGColor(gray: 1, alpha: 1),
                scrollbar: nil
            )
        )

        #expect(frame.displayedLayoutSize == CGSize(width: 1000, height: 600))
    }
}
