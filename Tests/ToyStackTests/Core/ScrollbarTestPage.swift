import CoreGraphics
import Foundation
import Testing

@testable import Engine

@MainActor
struct ScrollbarTestPage {
    let browser: Browser
    let frame: Frame
    let paths: [String]

    static func open() async throws -> ScrollbarTestPage {
        let id: String = UUID().uuidString
        let tracePath: String = NSTemporaryDirectory() + "scrollbar-\(id).trace"
        let pagePath: String = NSTemporaryDirectory() + "scrollbar-\(id).html"
        let html: String = #"<p>start</p><div style="height: 6000px;"></div><p>end</p>"#
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)

        let browser: Browser = Browser(tracePath: tracePath)
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()

        let tab: BrowserTab = try #require(browser.activeTab)
        let page: ScrollbarTestPage = ScrollbarTestPage(browser: browser, frame: tab.rootFrame, paths: [tracePath, pagePath])
        try #require(await page.settle(until: { tab.isLoaded && !tab.rootFrame.displayList.isEmpty }))
        return page
    }

    func settle(until condition: () -> Bool = { true }) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            browser.advanceFrame()
            if browser.isRenderIdle, condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return false
    }

    func close() {
        browser.stopAnimationTimer()
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
