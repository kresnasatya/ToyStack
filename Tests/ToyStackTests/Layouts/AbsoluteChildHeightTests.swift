import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct AbsoluteChildHeightTests {
    private let css: String = """
        body { display: block; }
        section { display: block; }
        div { display: block; }
        p { display: block; }
        .abs { position: absolute; }
    """

    private func boxHeight(_ page: LayoutTestPage, id: String) throws -> CGFloat {
        let element: ElementRef = try #require(page.firstElement(id: id))
        let layoutID: LayoutID = try #require(element.ref.layoutID)
        let bounds: Rect = page.tree.absoluteBounds(layoutID)
        return bounds.bottom - bounds.top
    }

    // CSS 2.1 §10.6.3: an absolutely positioned child is ignored for its parent's height,
    // and §9.6: it has no impact on later siblings, so it does not hide the children after it.
    @Test func inFlowChildrenAfterAnAbsoluteChildStillCount() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<section id="with"><div class="abs">decoration</div><p>one</p><p>two</p></section><section id="without"><p>one</p><p>two</p></section>"#,
            rules: css
        )
        let expected: CGFloat = try boxHeight(page, id: "without")
        #expect(expected > 0)
        #expect(try boxHeight(page, id: "with") == expected)
        expectIncrementalMatchesFull(page)
    }

    @Test func absoluteChildInTheMiddleDoesNotPushTheNextSiblingDown() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<section id="with"><p>one</p><div class="abs">decoration</div><p id="after-abs">two</p></section><section id="without"><p>one</p><p id="plain">two</p></section>"#,
            rules: css
        )
        #expect(try boxHeight(page, id: "with") == boxHeight(page, id: "without"))
        let withTop: CGFloat = try top(page, id: "after-abs") - top(page, id: "with")
        let withoutTop: CGFloat = try top(page, id: "plain") - top(page, id: "without")
        #expect(withTop == withoutTop)
        expectIncrementalMatchesFull(page)
    }

    private func top(_ page: LayoutTestPage, id: String) throws -> CGFloat {
        let element: ElementRef = try #require(page.firstElement(id: id))
        let layoutID: LayoutID = try #require(element.ref.layoutID)
        return page.tree.absoluteBounds(layoutID).top
    }

    @Test func onlyAbsoluteChildrenGiveZeroHeight() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<section id="s"><div class="abs">a</div><div class="abs">b</div></section>"#,
            rules: css
        )
        #expect(try boxHeight(page, id: "s") == 0)
    }

    @Test func switchingPositionMovesTheNextSibling() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<section id="s"><p>one</p><div id="box" class="abs">decoration</div><p id="next">two</p></section>"#,
            rules: css
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let absoluteTop: CGFloat = try top(page, id: "next")

        InlineStyle.set(box, property: "position", value: "static")
        page.frame.setNeedsRender()
        page.frame.render()
        let staticTop: CGFloat = try top(page, id: "next")
        #expect(staticTop > absoluteTop)
        expectIncrementalMatchesFull(page)

        InlineStyle.set(box, property: "position", value: "absolute")
        page.frame.setNeedsRender()
        page.frame.render()
        #expect(try top(page, id: "next") == absoluteTop)
        expectIncrementalMatchesFull(page)
    }
}
