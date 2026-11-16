import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ScrollbarDragTests {

    @Test func draggingTheThumbToTheBottomScrollsToTheEnd() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY + 600)
        page.browser.releaseScrollbar()

        #expect(abs(page.frame.scroll - page.frame.maxScroll) < 0.5)
    }

    @Test func pressingInsideTheThumbDoesNotJumpThePage() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY)

        #expect(page.frame.scroll == 0)
    }

    @Test func draggingAboveTheTopClampsToTheStart() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY + 200)
        page.browser.dragScrollbar(y: -400)

        #expect(page.frame.scroll == 0)
    }

    @Test func pressOnThePageLeavesScrollToTheWheel() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }

        #expect(!page.browser.pressScrollbar(x: 400, y: 10))
        page.browser.dragScrollbar(y: 500)

        #expect(!page.browser.isPressingScrollbar)
        #expect(page.frame.scroll == 0)
    }

    @Test func movesAfterReleaseDoNotScroll() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.midY))
        page.browser.releaseScrollbar()
        page.browser.dragScrollbar(y: thumb.midY + 300)

        #expect(page.frame.scroll == 0)
    }

    @Test func aLostReleaseDoesNotLetTheNextPagePressScroll() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.midY))
        #expect(!page.browser.pressScrollbar(x: 400, y: 10))
        page.browser.dragScrollbar(y: thumb.midY + 300)

        #expect(!page.browser.isPressingScrollbar)
        #expect(page.frame.scroll == 0)
    }

    @Test func zoomedPageScrollHalfwayWhenTheThumbMovesHalfItsTravel() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        page.browser.setZoom(2)
        try #require(await page.settle())
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)
        let travel: CGFloat = page.browser.windowSize.height - thumb.height

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.midY))
        page.browser.dragScrollbar(y: thumb.midY + travel / 2)

        #expect(abs(page.frame.scroll - page.frame.maxScroll / 2) < 0.5)
    }
}
