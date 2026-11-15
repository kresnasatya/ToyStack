import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct HoverTraceTests {

    @Test func onlyARenderAfterAPointerMoveTracesTheHoverCheck() throws {
        let path: String = NSTemporaryDirectory() + "hover-trace-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">content</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
            """
        )
        let browser: Browser = Browser(tracePath: path)
        page.tab.browser = browser

        page.frame.setNeedsRender()
        page.frame.render()
        page.tab.hover(x: 10, y: 10)
        page.frame.render()
        page.frame.render()
        browser.measure.close()

        let trace: String = try String(contentsOfFile: path, encoding: .utf8)
        let begins: Int = trace.components(separatedBy: #""ph": "B", "cat": "input", "name": "BrowserTab.hover""#).count - 1
        #expect(begins == 1)
    }
}
