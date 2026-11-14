import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ResizeLayoutStartTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func resizeStartsThePassWithoutATick() async throws {
        let (browser, pagePath): (Browser, String) = try await Self.loadedBrowser(asyncLayout: true)
        defer { try? FileManager.default.removeItem(atPath: pagePath) }
        let frame: Frame = try #require(browser.activeTab?.rootFrame)

        browser.resize(to: CGSize(width: 500, height: 600), deferLayout: true)

        #expect(frame.isLayoutInFlight, "the pass waited for the animation tick")
        #expect(await Self.pump({ !frame.isLayoutInFlight }))
        #expect(frame.installedLayoutSize.width == 500)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func resizeDuringAPassLetsItFinish() async throws {
        let tracePath: String = NSTemporaryDirectory() + "resize-start-\(UUID().uuidString).trace"
        let (browser, pagePath): (Browser, String) = try await Self.loadedBrowser(
            asyncLayout: true,
            tracePath: tracePath
        )
        defer {
            try? FileManager.default.removeItem(atPath: pagePath)
            try? FileManager.default.removeItem(atPath: tracePath)
        }
        let frame: Frame = try #require(browser.activeTab?.rootFrame)

        browser.resize(to: CGSize(width: 500, height: 600), deferLayout: true)
        browser.resize(to: CGSize(width: 450, height: 600), deferLayout: true)
        #expect(await Self.pump({ !frame.isLayoutInFlight }))
        #expect(frame.installedLayoutSize.width == 450)

        browser.stopAnimationTimer()
        let data: Data = try Data(contentsOf: URL(fileURLWithPath: tracePath))
        let root: [String: Any] = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let events: [[String: Any]] = try #require(root["traceEvents"] as? [[String: Any]])
        let superseded: [Int] = events
            .filter({ $0["name"] as? String == "layout.async.superseded" })
            .compactMap({ ($0["args"] as? [String: Any])?["width"] as? Int })
        #expect(superseded == [500], "the pass was not installed: \(superseded)")
    }

    @Test func syncLayoutResizeWaitsForTheTick() async throws {
        let (browser, pagePath): (Browser, String) = try await Self.loadedBrowser(asyncLayout: false)
        defer { try? FileManager.default.removeItem(atPath: pagePath) }
        let frame: Frame = try #require(browser.activeTab?.rootFrame)

        browser.resize(to: CGSize(width: 500, height: 600), deferLayout: true)
        #expect(frame.paintedLayoutSize.width == 800, "a synchronous layout ran inside the resize event")

        browser.advanceFrame()
        #expect(frame.paintedLayoutSize.width == 500)
    }

    // MARK: - Helpers

    private static func loadedBrowser(
        asyncLayout: Bool,
        tracePath: String? = nil
    ) async throws -> (Browser, String) {
        let pagePath: String = NSTemporaryDirectory() + "resize-start-\(UUID().uuidString).html"
        let html: String = (0..<20).map { (index: Int) -> String in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)
        let browser: Browser = Browser(tracePath: tracePath)
        browser.usesAsyncLayout = asyncLayout
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()
        try #require(await pump({ browser.activeTab?.isLoaded == true }))
        try #require(await settle(browser, untilWidth: 800 * browser.pageZoom))
        return (browser, pagePath)
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
