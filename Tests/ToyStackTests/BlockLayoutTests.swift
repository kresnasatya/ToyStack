import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct BlockLayoutTests {
    @Test func inputKeepsContainingBlockWidth() throws {
        let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 800)
        let frame: Frame = tab.rootFrame
        frame.replaceDOM(HTMLParser(body: #"<p>name<input></p>"#).parse())

        frame.setStyleRules(CSSParser("""
            html { width: 400px; }
            body { display: block; }
            p { display: block; }
            """).parse().rules)
        frame.setNeedsRender()
        frame.render()

        let p: ElementRef = try #require(
            treeToList(frame.nodes).compactMap({ $0.element }).first(where: { $0.tag == "p" })
        )
        let block: LayoutRef = try #require(p.ref.layout)
        let parentWidth: CGFloat = try #require(block.parent?.width)
        #expect(block.width == parentWidth)
        #expect(block.width == CGFloat(400))

        let layoutInput: LayoutRef = try #require(
            treeToList(block).first(where: { ref in
                if case .embed(.input) = ref.kind { return true }
                return false
            })
        )
        #expect(layoutInput.width == inputWidthPx)
    }
}
