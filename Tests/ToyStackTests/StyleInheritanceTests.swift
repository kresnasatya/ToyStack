import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleInheritanceTests {
    @Test func mediaFontSizeFlipUpdatesInheritedDescendant() throws {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let frame: Frame = tab.rootFrame
        let dom: DOMTree = HTMLParser(body: #"<div class="narrow"><p id="child">hello</p></div>"#).parse()
        frame.replaceDOM(dom)
        frame.setStyleRules(CSSParser("""
            html { width: 600px; }
            div { font-size: 10px; }
            p { font-size: 150%; }
            @media (min-width: 600px) { div.narrow { font-size: 20px; } }
            """).parse().rules)
        frame.setNeedsRender()
        frame.render()

        let child: ElementRef = try #require(
            treeToList(dom.ref(dom.root)).compactMap(\.element)
                .first(where: { $0.attributes["id"] == "child" })
        )
        #expect(child.style.computed.text.font.size == 30)

        frame.setViewport(width: 400, height: frame.frameHeight)
        frame.setNeedsViewportResize()
        frame.render()

        #expect(child.style.computed.text.font.size == 15)
    }
}
