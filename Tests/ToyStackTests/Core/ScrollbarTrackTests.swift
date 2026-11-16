import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ScrollbarTrackTests {

    @Test func pressBelowTheThumbScrollsDownOnePage() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.maxY + 100))

        #expect(page.frame.scroll == 560)
    }

    @Test func pressAboveTheThumbScrollsUpOnePage() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        page.browser.activeTab?.scrollTo(offset: 2000)
        try #require(await page.settle())
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.minY - 10))

        #expect(page.frame.scroll == 1440)
    }

    @Test func pressBelowTheThumbNearTheEndStopsAtTheBottom() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        page.browser.activeTab?.scrollTo(offset: page.frame.maxScroll - 100)
        try #require(await page.settle())
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)
        try #require(thumb.maxY < 599)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: 599))

        #expect(page.frame.scroll == page.frame.maxScroll)
    }

    @Test func pressesFasterThanTheRepaintEachAddAPage() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        for _ in 0..<5 {
            #expect(page.browser.pressScrollbar(x: thumb.midX, y: 590))
            page.browser.releaseScrollbar()
        }

        #expect(page.frame.scroll == 2800)
    }

    @Test func draggingAfterATrackPressDoesNotMoveThePage() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.maxY + 100))
        page.browser.dragScrollbar(y: 0)

        #expect(page.browser.isPressingScrollbar)
        #expect(page.frame.scroll == 560)

        page.browser.releaseScrollbar()

        #expect(!page.browser.isPressingScrollbar)
    }

    @Test func zoomedPagePagesByTheWindowHeight() async throws {
        let page: ScrollbarTestPage = try await ScrollbarTestPage.open()
        defer { page.close() }
        page.browser.setZoom(2)
        try #require(await page.settle())
        let thumb: CGRect = try #require(page.browser.activeSidebar?.frame)

        #expect(page.browser.pressScrollbar(x: thumb.midX, y: thumb.maxY + 100))

        #expect(page.frame.scroll == 280)
    }
}
