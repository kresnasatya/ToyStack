import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct HorizontalMarginLayoutTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        """

    private func page(_ rules: String) -> LayoutTestPage {
        return LayoutTestPage(
            html: #"<div id="box"><div id="inner">text</div></div>"#,
            rules: Self.baseRules + rules
        )
    }

    @Test func autoWidthBlockShrinksBetweenItsMargins() throws {
        let page: LayoutTestPage = page("#box { margin-left: 20px; margin-right: 30px; }")
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        #expect(page.tree.x(box) == page.tree.x(body) + 20)
        #expect(page.tree.width(box) == page.tree.width(body) - 50)
    }

    @Test func childrenStartInsideTheMarginBox() throws {
        let page: LayoutTestPage = page("#box { margin-left: 20px; padding-left: 5px; border: 2px solid black; }")
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let inner: LayoutID = try #require(page.firstElement(id: "inner")?.ref.layoutID)
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        #expect(page.tree.selfRect(box).left == page.tree.x(body) + 20)
        #expect(page.tree.x(inner) == page.tree.x(body) + 27)
    }

    @Test func fixedWidthIgnoresTheRightMargin() throws {
        let page: LayoutTestPage = page("#box { width: 100px; margin-left: 10px; margin-right: 400px; }")
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        #expect(page.tree.x(box) == page.tree.x(body) + 10)
        #expect(page.tree.width(box) == 100)
    }

    @Test func negativeRightMarginWidensAnAutoWidthBlock() throws {
        let page: LayoutTestPage = page("#box { margin-right: -40px; }")
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        #expect(page.tree.width(box) == page.tree.width(body) + 40)
    }

    @Test func zoomScalesHorizontalMargins() throws {
        let page: LayoutTestPage = page("#box { zoom: 2; margin-left: 10px; margin-right: 15px; }")
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        #expect(page.tree.x(box) == page.tree.x(body) + 20)
        #expect(page.tree.width(box) == page.tree.width(body) - 50)
    }

    @Test func marginChangeRelaysOutLikeAFullBuild() throws {
        let page: LayoutTestPage = page("#box { margin-left: 20px; }")
        let box: ElementRef = try #require(page.firstElement(id: "box"))

        InlineStyle.set(box, property: "margin-left", value: "60px")
        InlineStyle.set(box, property: "margin-right", value: "10px")
        page.frame.setNeedsStyle(box.ref)
        page.frame.render()

        let id: LayoutID = try #require(box.ref.layoutID)
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        #expect(page.tree.x(id) == page.tree.x(body) + 60)
        #expect(page.tree.width(id) == page.tree.width(body) - 70)
        expectIncrementalMatchesFull(page)
    }
}
