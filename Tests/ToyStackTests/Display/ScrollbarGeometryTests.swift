import CoreGraphics
import Testing

@testable import Engine

struct ScrollbarGeometryTests {

    private func geometry(docHeight: CGFloat, contentHeight: CGFloat = 600, scroll: CGFloat = 0) -> ScrollbarGeometry {
        return ScrollbarGeometry(docHeight: docHeight, contentHeight: contentHeight, contentWidth: 800, scroll: scroll)
    }

    @Test func aPageThatFitsHasNoThumbToGrab() {
        let bar: ScrollbarGeometry = geometry(docHeight: 600)

        #expect(bar.thumbRect == nil)
        #expect(!bar.thumbGrabContains(x: 795, y: 10))
    }

    @Test func thumbTopPastEitherEndClampsToTheScrollRange() {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000)

        #expect(bar.scroll(forThumbTop: -500) == 0)
        #expect(bar.scroll(forThumbTop: 0) == 0)
        #expect(bar.scroll(forThumbTop: bar.thumbTravel) == bar.maxScroll)
        #expect(bar.scroll(forThumbTop: 10_000) == bar.maxScroll)
    }

    @Test func pressBesideTheThinThumbStillGrabsIt() throws {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000)
        let thumb: Rect = try #require(bar.thumbRect)
        let midY: CGFloat = (thumb.top + thumb.bottom) / 2

        #expect(bar.thumbGrabContains(x: 799, y: midY))
        #expect(bar.thumbGrabContains(x: 789, y: midY))
        #expect(!bar.thumbGrabContains(x: 787, y: midY))
        #expect(!bar.thumbGrabContains(x: 795, y: thumb.bottom + 1))
    }

    @Test func viewportShorterThanTheMinimumThumbKeepsTheCurrentScroll() {
        let bar: ScrollbarGeometry = geometry(docHeight: 300, contentHeight: 20, scroll: 400)

        #expect(bar.thumbTravel < 0)
        #expect(bar.scroll(forThumbTop: 5) == 400)
    }
}
