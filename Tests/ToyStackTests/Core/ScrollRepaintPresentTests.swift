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

        #expect(await page.waitUntilRepainted())

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

    @Test func scrollLeavingTheInterestRegionShowsBeforeTheRepaint() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }
        let frame: Frame = page.frame
        let height: CGFloat = frame.frameHeight
        try #require(frame.maxScroll > 4 * height)

        page.scroll(by: 1.9 * height)
        try #require(await page.waitUntilRepainted())
        let before: CGFloat = frame.scroll

        // The interest region still starts at 0 and ends 4 viewports down, so
        // this scroll leaves it while the content painted at 1.9 viewports
        // still covers the whole viewport.
        page.scroll(by: 1.55 * height)

        #expect(frame.scroll > before)
        #expect(page.browser.activeTabScroll == frame.scroll)
    }

    @Test func leavingTheInterestRegionPresentsBeforeTheRepaintRuns() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }

        let afterRepaint: Bool? = try await leaveInterestRegion(page, thenRun: {})

        #expect(afterRepaint == false)
    }

    @Test func aTickBeforeTheScrollIsPresentedDoesNotRepaintFirst() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }

        let afterRepaint: Bool? = try await leaveInterestRegion(page, thenRun: {
            page.browser.advanceFrame()
        })

        #expect(afterRepaint == false)
    }

    /// Leaves the interest region while the painted content still covers the
    /// viewport, runs `action` before the scroll's tiles come back, and tells
    /// whether the scroll was first presented after its repaint. The tiles are
    /// drawn off the main thread but presented on it, so a repaint that takes
    /// the main thread first holds the scroll back until the repaint is done.
    private func leaveInterestRegion(
        _ page: ScrollTestBrowser,
        thenRun action: () -> Void
    ) async throws -> Bool? {
        let frame: Frame = page.frame
        let height: CGFloat = frame.frameHeight
        try #require(frame.maxScroll > 4 * height)

        page.scroll(by: 1.9 * height)
        try #require(await page.waitUntilRepainted())

        var presents: [(scroll: CGFloat, afterRepaint: Bool)] = []
        page.browser.onPresent = { (presented: PresentedFrame) in
            presents.append((presented.viewport.contentOffset.scroll, !frame.scrollNeedsPaint()))
        }
        page.scroll(by: 1.55 * height)
        let target: CGFloat = frame.scroll * page.browser.pageZoom
        action()

        try #require(await page.waitUntilRepainted())
        return presents.first(where: { $0.scroll == target })?.afterRepaint
    }

    @Test func aFlickOfAlmostOneViewportAfterARepaintShowsAtOnce() async throws {
        let page: ScrollTestBrowser = try await ScrollTestBrowser.open()
        defer { page.close() }
        let frame: Frame = page.frame
        let height: CGFloat = frame.frameHeight
        try #require(frame.maxScroll > 3 * height)

        page.scroll(by: 1.1 * height)
        try #require(await page.waitUntilRepainted())
        let before: CGFloat = frame.scroll

        page.scroll(by: 0.95 * height)

        #expect(frame.scroll > before)
        #expect(page.browser.activeTabScroll == frame.scroll)
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

    func waitUntil(_ condition: () -> Bool) async -> Bool {
        return await ScrollTestBrowser.pump(condition)
    }

    /// The scroll repaint has run and every raster it started has landed, with
    /// the animation timer paused, so nothing but the scroll itself drove it.
    func waitUntilRepainted() async -> Bool {
        return await waitUntil({ !frame.scrollNeedsPaint() && browser.isRenderIdle })
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
