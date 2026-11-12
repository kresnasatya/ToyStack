import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct FontChangeTraceTests {
    /// A breakpoint flip changes the font of every node. The trace must stay
    /// small: one event per tag, not one per node, or tracing slows the pass.
    @Test func breakpointFlipWritesOneFontEventPerTag() throws {
        let path: String = NSTemporaryDirectory() + "font-change-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let paragraphs: String = (0..<60).map({ "<p>Paragraph \($0) <em>with</em> words</p>" }).joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: paragraphs,
            rules: """
                html { width: 600px; font-size: 24px; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                body { display: block; }
                p { display: block; }
                """
        )
        let browser: Browser = Browser(tracePath: path)
        page.tab.browser = browser
        page.frame.clearPaintRequest()

        page.tab.resize(width: 900, height: 600)
        page.frame.render()
        page.tab.resize(width: 700, height: 600)
        page.frame.render()
        browser.measure.close()

        let trace: String = try String(contentsOfFile: path, encoding: .utf8)
        let events: Int = trace.components(separatedBy: "\"style.font-size.changed.").count - 1
        #expect(events > 0, "the flip should still be traced")
        #expect(events <= 12, "one event per changed node: \(events) events")
    }
}
