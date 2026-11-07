import CoreGraphics
import Foundation
import Testing

@testable import Engine

// Like the other background layout suites, this one is opt-in because the
// worker records into the process-wide profiler.
@Suite(.serialized)
@MainActor
struct AsyncLayoutTraceTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func asyncLayoutAndStaleDiscardAppearInTheTrace() async throws {
        let path: String = NSTemporaryDirectory() + "async-layout-trace-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let html: String = (0..<40).map { index in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; }"
        )
        let browser: Browser = Browser(tracePath: path)
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        page.frame.clearPaintRequest()

        // Start a pass, then change the width so its result is stale.
        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        page.tab.resize(width: 300, height: 600)
        page.frame.runAnimationFrame()
        let deadline: Date = Date().addingTimeInterval(5)
        while page.frame.isLayoutInFlight, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        browser.measure.close()

        let trace: String = try String(contentsOfFile: path, encoding: .utf8)
        #expect(trace.contains("\"name\": \"layout.async.start\""))
        #expect(trace.contains("\"name\": \"layout.async.start.inputs\""))
        #expect(trace.contains("\"name\": \"layout.async.start.tree\""))
        #expect(trace.contains("\"name\": \"layout.async.start.refresh\""))
        #expect(trace.contains("\"name\": \"layout.async.document\""))
        #expect(trace.contains("\"name\": \"layout.async.finish\""))
        #expect(trace.contains("\"name\": \"layout.async.discarded\""))
    }
}
