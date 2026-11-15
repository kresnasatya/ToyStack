import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct AsyncResizeCompositeTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func finishedPassReachesTheTiles() async throws {
        let (browser, pagePath): (Browser, String) = try await Self.loadedBrowser()
        defer {
            browser.stopAnimationTimer()
            try? FileManager.default.removeItem(atPath: pagePath)
        }
        let frame: Frame = try #require(browser.activeTab?.rootFrame)
        try #require(Self.widestText(browser.drawList) > 500, "the page does not reach past 500 px at 800")

        browser.resize(to: CGSize(width: 500, height: 600), deferLayout: true)
        #expect(await Self.pump({ !frame.isLayoutInFlight }))
        #expect(await Self.settle(browser, untilWidth: 500 * browser.pageZoom))

        let widest: CGFloat = Self.widestText(browser.drawList)
        #expect(widest <= frame.paintedLayoutSize.width, "the tiles still show an older layout: text reaches \(widest) in a \(frame.paintedLayoutSize.width) px layout")
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func passSupersededByADragReachesTheTiles() async throws {
        let (browser, pagePath): (Browser, String) = try await Self.loadedBrowser()
        defer {
            browser.stopAnimationTimer()
            try? FileManager.default.removeItem(atPath: pagePath)
        }
        let frame: Frame = try #require(browser.activeTab?.rootFrame)

        browser.resize(to: CGSize(width: 600, height: 600), deferLayout: true)
        browser.resize(to: CGSize(width: 450, height: 600), deferLayout: true)
        #expect(await Self.pump({ !frame.isLayoutInFlight }))
        #expect(await Self.settle(browser, untilWidth: 450 * browser.pageZoom))

        let widest: CGFloat = Self.widestText(browser.drawList)
        #expect(widest <= frame.paintedLayoutSize.width, "the tiles still show an older layout: text reaches \(widest) in a \(frame.paintedLayoutSize.width) px layout")
    }

    // MARK: - Helpers

    private static func widestText(_ drawList: [DisplayOp]) -> CGFloat {
        var widest: CGFloat = 0
        for op in drawList {
            guard case .compositedLayer(let layer, _, _, _) = op else { continue }
            for item in layer.content.items {
                guard case .text(_, _, _, let rect) = item else { continue }
                widest = max(widest, rect.right)
            }
        }
        return widest
    }

    private static func loadedBrowser() async throws -> (Browser, String) {
        let pagePath: String = NSTemporaryDirectory() + "resize-composite-\(UUID().uuidString).html"
        let html: String = (0..<20).map { (index: Int) -> String in
            "<p>Paragraph \(index) has enough words to fill a wide line and wrap into several lines when the window gets narrow.</p>"
        }.joined()
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()
        try #require(await pump({ browser.activeTab?.isLoaded == true }))
        try #require(await settle(browser, untilWidth: 800 * browser.pageZoom))
        try #require(browser.activeTab?.rootFrame).runAnimationFrame()
        return (browser, pagePath)
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
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
}
