import CoreGraphics
import Foundation
import Testing

@testable import Engine

// Opt-in for the same reason as BackgroundLayoutTests.
@Suite(.serialized)
@MainActor
struct BackgroundLayoutProfileTests {
    /// The GUI lays out on a background thread. Its trace must still carry
    /// the layout breakdown, written on the layout lane for the frame that
    /// started the job.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func backgroundLayoutWritesItsOwnLayoutProfile() async throws {
        let path: String = NSTemporaryDirectory() + "background-profile-\(UUID().uuidString).trace"
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

        browser.beginFrame()
        let jobFrame: Int = browser.measure.frame
        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        browser.beginFrame()
        let deadline: Date = Date().addingTimeInterval(5)
        while page.frame.isLayoutInFlight, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(!page.frame.isLayoutInFlight)
        browser.measure.close()

        let data: Data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root: [String: Any] = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let events: [[String: Any]] = try #require(root["traceEvents"] as? [[String: Any]])
        var lanes: [Int: String] = [:]
        for event in events where event["name"] as? String == "thread_name" {
            if let tid: Int = event["tid"] as? Int,
                let args: [String: Any] = event["args"] as? [String: Any]
            {
                lanes[tid] = args["name"] as? String
            }
        }
        let layoutProfiles: [[String: Any]] = events.filter({ event in
            guard event["name"] as? String == "profile.layout",
                let tid: Int = event["tid"] as? Int
            else { return false }
            return lanes[tid] == "browser.layout"
        })
        let profile: [String: Any] = try #require(
            layoutProfiles.first?["args"] as? [String: Any],
            "no profile.layout on the browser.layout lane"
        )
        #expect((profile["layout.visited.count"] as? Int ?? 0) > 0)
        #expect(profile["frame"] as? Int == jobFrame)
        #expect(browser.usesAsyncLayout)
    }
}
