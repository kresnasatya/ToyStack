import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct BlockLayoutTests {
    @Test func inputKeepsContainingBlockWidth() throws {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let frame: Frame = tab.rootFrame!
        let html: Element = Element(tag: "html", attributes: [:], parent: nil)
        let body: Element = Element(tag: "body", attributes: [:], parent: html)
        let p: Element = Element(tag: "p", attributes: [:], parent: body)
        let text: TextNode = TextNode(text: "name", parent: p)
        let input: Element = Element(tag: "input", attributes: [:], parent: p)
        p.children = [text, input]
        body.children = [p]
        html.children = [body]

        frame.nodes = html
        frame.rules = CSSParser("""
            html { width: 400px; }
            body { display: block; }
            p { display: block; }
            """).parse().rules
        frame.needsStyle = true
        frame.render()

        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        let parentWidth: CGFloat = try #require(block.parent?.width)
        #expect(block.width == parentWidth)
        #expect(block.width == CGFloat(400))

        let layoutInput: InputLayout = try #require(treeToList(block).compactMap({ $0 as? InputLayout }).first)
        #expect(layoutInput.width == InputLayout.inputWidthPx)
    }
}
