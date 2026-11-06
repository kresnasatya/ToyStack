import CoreGraphics
import Foundation
import Testing

@testable import Engine

// Background layout records into the process-wide profiler, so this suite is
// opt-in for the same reason as BackgroundLayoutTests.
@Suite(.serialized)
@MainActor
struct AsyncResizeRestartTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func frameClockRestartsLayoutAfterAStaleResult() async throws {
        let html: String = (0..<40).map { index in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; }"
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        // The page loaded and painted before the resize.
        page.frame.clearPaintRequest()

        // A layout for 400 starts.
        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        let started: Bool = page.frame.isLayoutInFlight
        #expect(started)

        // Resize while it runs; this tick consumes the render request.
        page.tab.resize(width: 300, height: 600)
        page.frame.runAnimationFrame()
        let stillRunning: Bool = page.frame.isLayoutInFlight
        #expect(stillRunning)

        // The 400 result is discarded as stale. Nothing else invalidates.
        let deadline: Date = Date().addingTimeInterval(5)
        while page.frame.isLayoutInFlight, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        page.frame.clearPaintRequest()

        // The frame clock alone must start the pass for the latest width.
        page.frame.runAnimationFrame()
        let restarted: Bool = page.frame.isLayoutInFlight
        let asyncOn: Bool = browser.usesAsyncLayout   // also keeps the weak tab.browser alive
        #expect(asyncOn)
        #expect(restarted, "the final width never restarted after the stale discard")
    }
}
