import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct RootPseudoClassTests {
    @Test func rootMatchesOnlyTheDocumentElement() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="x">text</div>"#,
            rules: ":root { background-color: #ff0000; } div:root { width: 5px; }"
        )
        let html: ElementRef = try #require(page.firstElement(tag: "html"))
        let body: ElementRef = try #require(page.firstElement(tag: "body"))
        let div: ElementRef = try #require(page.firstElement(id: "x"))
        #expect(html.style.computed.visual.background.color == BrowserColor(red: 1, green: 0, blue: 0))
        #expect(body.style.computed.visual.background.color == nil)
        #expect(div.style.computed.visual.background.color == nil)
        #expect(div.style.computed.box.size.width == nil)
    }
}
