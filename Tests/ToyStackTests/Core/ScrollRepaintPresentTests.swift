import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ScrollRepaintPresentTests {
    @Test func scrollNearTheEndOfThePaintedContentShowsBeforeTheRepaint() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }
        let frame: Frame = page.frame
        let target: CGFloat = 2 * frame.frameHeight - 10
        try #require(frame.maxScroll > target)

        page.scroll(by: target)

        #expect(frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == target)

        page.browser.advanceFrame()

        #expect(!frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == target)
    }

    @Test func scrollPastThePaintedContentWaitsForTheRepaint() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }
        let frame: Frame = page.frame
        let target: CGFloat = frame.maxScroll
        try #require(target > 4 * frame.frameHeight)

        page.scroll(by: target)

        #expect(frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == 0)

        page.browser.advanceFrame()

        #expect(!frame.scrollNeedsPaint())
        #expect(page.browser.activeTabScroll == target)
    }
}

// MARK: - ScrollTestBrowser

@MainActor
private struct ScrollTestBrowser {
    let browser: Browser
    let frame: Frame
    let paths: [String]

    static func open() async throws -> ScrollTestBrowser {
        let id: String = UUID().uuidString
        let tracePath: String = NSTemporaryDirectory() + "scroll-repaint-\(id).trace"
        let pagePath: String = NSTemporaryDirectory() + "scroll-repaint-\(id).html"
        let html: String = #"<p>start</p><div style="height: 6000px;"></div><p>end</p>"#
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)

        let browser: Browser = Browser(tracePath: tracePath)
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()

        let tab: BrowserTab = try #require(browser.activeTab)
        try #require(await pump({ tab.isLoaded }))
        try #require(await settle(browser, until: { !tab.rootFrame.displayList.isEmpty }))
        return ScrollTestBrowser(browser: browser, frame: tab.rootFrame, paths: [tracePath, pagePath])
    }

    func scroll(by offset: CGFloat) {
        browser.activeTab?.scrollBy(deltaY: -offset * browser.pageZoom)
    }

    func close() {
        browser.stopAnimationTimer()
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }

    private static func settle(_ browser: Browser, until condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            browser.advanceFrame()
            _ = await pump({ browser.isRenderIdle })
            if browser.isRenderIdle, condition() {
                return true
            }
        }
        return false
    }
}
