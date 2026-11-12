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
        let document: LayoutTree = try #require(frame.document)
        let block: LayoutID = try #require(p.ref.layoutID)
        let parentID: LayoutID = try #require(document.parentID(of: block))
        let parentWidth: CGFloat = document.width(parentID)
        #expect(document.width(block) == parentWidth)
        #expect(document.width(block) == CGFloat(400))

        let layoutInput: LayoutID = try #require(
            treeToList(document, block).first(where: { id in
                if case .embed(.input) = document.kind(id) { return true }
                return false
            })
        )
        #expect(document.width(layoutInput) == inputWidthPx)
    }
}
