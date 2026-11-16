import CoreGraphics
import Testing

@testable import Engine

struct ScrollbarGeometryTests {

    private func geometry(docHeight: CGFloat, contentHeight: CGFloat = 600, scroll: CGFloat = 0) -> ScrollbarGeometry {
        return ScrollbarGeometry(docHeight: docHeight, contentHeight: contentHeight, contentWidth: 800, scroll: scroll)
    }

    @Test func aPageThatFitsHasNoScrollbarToPress() {
        let bar: ScrollbarGeometry = geometry(docHeight: 600)

        #expect(bar.thumbRect == nil)
        #expect(!bar.thumbGrabContains(x: 795, y: 10))
        #expect(bar.trackPageDelta(x: 795, y: 500) == nil)
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

    @Test func pressOnTheTrackPagesTowardThePress() throws {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000, scroll: 900)
        let thumb: Rect = try #require(bar.thumbRect)

        #expect(bar.trackPageDelta(x: 795, y: thumb.top - 1) == -560)
        #expect(bar.trackPageDelta(x: 795, y: 0) == -560)
        #expect(bar.trackPageDelta(x: 795, y: thumb.bottom) == 560)
        #expect(bar.trackPageDelta(x: 789, y: 599) == 560)
    }

    @Test func pressOnTheThumbOrOffTheTrackDoesNotPage() throws {
        let bar: ScrollbarGeometry = geometry(docHeight: 3000, scroll: 900)
        let thumb: Rect = try #require(bar.thumbRect)

        #expect(bar.trackPageDelta(x: 795, y: (thumb.top + thumb.bottom) / 2) == nil)
        #expect(bar.trackPageDelta(x: 787, y: thumb.bottom + 10) == nil)
        #expect(bar.trackPageDelta(x: 795, y: -1) == nil)
        #expect(bar.trackPageDelta(x: 795, y: 600) == nil)
    }

    @Test func aPageKeepsSomeOfThePreviousViewInSight() {
        #expect(geometry(docHeight: 3000).pageStep == 560)
        #expect(geometry(docHeight: 3000, contentHeight: 240).pageStep == 210)
    }

    @Test func viewportShorterThanTheMinimumThumbKeepsTheCurrentScroll() {
        let bar: ScrollbarGeometry = geometry(docHeight: 300, contentHeight: 20, scroll: 400)

        #expect(bar.thumbTravel < 0)
        #expect(bar.scroll(forThumbTop: 5) == 400)
    }
}
