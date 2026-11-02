import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutTreePruningTests {
    @Test func replacedLayoutNodesLeaveTheArena() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="a">one</div><div id="b">two</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                """
        )
        let tree: LayoutTree = try #require(page.frame.document)
        let before: Int = tree.liveIDs.count
        let b: Element = try #require(page.firstElement(id: "b"))
        b.style.mutate { $0.layout.display = .none }
        page.frame.setNeedsStyle(b)
        page.frame.render()

        let after: Int = try #require(page.frame.document).liveIDs.count
        #expect(after <= before)
    }
}
