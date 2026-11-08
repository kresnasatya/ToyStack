import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct BreakpointInheritanceStopTests {

    @Test func fixedFontSizeStopsARootFontFlip() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="fixed"><p id="inner">deep</p></div><p id="free">free</p>"#,
            rules: """
                html { width: 600px; font-size: 24px; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                body { display: block; }
                div, p { display: block; }
                #fixed { font-size: 20px; }
            """
        )
        let fixed: ElementRef = try #require(page.firstElement(id: "fixed"))
        let inner: ElementRef = try #require(page.firstElement(id: "inner"))
        let free: ElementRef = try #require(page.firstElement(id: "free"))
        #expect(free.style.computed.text.font.size == 18)
        let fixedRevision: UInt64 = fixed.style.revision
        let innerRevision: UInt64 = inner.style.revision

        page.frame.setViewport(width: 900, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.state.layout.tree.isDirty = false
        page.frame.render()
        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["style.visited"]?.count == 5)

        #expect(free.style.computed.text.font.size == 24)
        #expect(inner.style.computed.text.font.size == 20)
        #expect(fixed.style.revision == fixedRevision)
        #expect(inner.style.revision == innerRevision)
    }
}
