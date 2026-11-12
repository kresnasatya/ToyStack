import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct BrowserPresentedFrameTests {
    /// A present can be dispatched after a new width is painted but before its
    /// composite is installed. The frame still carries the old layers, so it
    /// must report the width those layers were laid out at.
    @Test func presentBeforeCompositeReportsTheShownLayoutWidth() async throws {
        let id: String = UUID().uuidString
        let tracePath: String = NSTemporaryDirectory() + "presented-frame-\(id).trace"
        let pagePath: String = NSTemporaryDirectory() + "presented-frame-\(id).html"
        defer {
            try? FileManager.default.removeItem(atPath: tracePath)
            try? FileManager.default.removeItem(atPath: pagePath)
        }
        let html: String = (0..<20).map { (index: Int) -> String in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)

        let browser: Browser = Browser(tracePath: tracePath)
        defer { browser.stopAnimationTimer() }
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()
        let zoom: CGFloat = browser.pageZoom

        #expect(await Self.pump({ browser.activeTab?.isLoaded == true }))
        #expect(await Self.settle(browser, untilWidth: 800 * zoom))

        browser.resize(to: CGSize(width: 500, height: 600))
        browser.advanceFrame()

        #expect(browser.activeTab?.rootFrame.paintedLayoutSize.width == 500)
        #expect(browser.presentedFrame.displayedLayoutSize.width == 800 * zoom)

        #expect(await Self.settle(browser, untilWidth: 500 * zoom))
    }

    private static func settle(_ browser: Browser, untilWidth width: CGFloat) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            browser.advanceFrame()
            _ = await pump({ browser.isRenderIdle })
            if browser.isRenderIdle, browser.presentedFrame.displayedLayoutSize.width == width {
                return true
            }
        }
        return false
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }
}
