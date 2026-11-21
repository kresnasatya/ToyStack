import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct FloatLayoutTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        """

    private func page(_ html: String, _ rules: String) -> LayoutTestPage {
        return LayoutTestPage(html: html, rules: Self.baseRules + rules)
    }

    private func id(_ page: LayoutTestPage, _ name: String) throws -> LayoutID {
        return try #require(page.firstElement(id: name)?.ref.layoutID)
    }

    private func bodyRect(_ page: LayoutTestPage) throws -> (left: CGFloat, right: CGFloat, top: CGFloat) {
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        let left: CGFloat = page.tree.x(body)
        return (left, left + page.tree.width(body), page.tree.y(body))
    }

    @Test func rightFloatSitsAgainstTheRightEdgeAndLeavesTheFlow() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="next"></div>"#,
            "#f { float: right; width: 100px; height: 50px; } #next { height: 10px; }"
        )
        let body = try bodyRect(page)
        let f: Rect = page.tree.selfRect(try id(page, "f"))
        let next: Rect = page.tree.selfRect(try id(page, "next"))
        #expect(f.right == body.right)
        #expect(f.left == body.right - 100)
        #expect(f.top == body.top)
        #expect(next.top == body.top)
    }

    @Test func leftFloatSitsAgainstTheLeftEdge() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="next"></div>"#,
            "#f { float: left; width: 100px; height: 50px; } #next { height: 10px; }"
        )
        let body = try bodyRect(page)
        let f: Rect = page.tree.selfRect(try id(page, "f"))
        #expect(f.left == body.left)
        #expect(page.tree.selfRect(try id(page, "next")).top == body.top)
    }

    @Test func floatAddsNothingToItsParentsHeight() throws {
        let page: LayoutTestPage = page(
            #"<div id="wrap"><div id="f"></div></div><div id="after"></div>"#,
            "#f { float: right; width: 100px; height: 50px; }"
        )
        #expect(page.tree.height(try id(page, "wrap")) == 0)
    }

    @Test func negativeRightMarginPushesTheFloatPastTheEdge() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div>"#,
            "#f { float: right; width: 100px; height: 10px; margin-right: -120px; }"
        )
        let body = try bodyRect(page)
        #expect(page.tree.selfRect(try id(page, "f")).left == body.right + 20)
    }

    @Test func clearMovesBelowAFloatInsideAnEarlierParent() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f"></div></div><div id="c"></div>"#,
            """
            #f { float: right; width: 100px; height: 80px; margin-bottom: 6px; }
            #c { float: right; clear: right; width: 100px; height: 20px; }
            """
        )
        let f: Rect = page.tree.selfRect(try id(page, "f"))
        let c: Rect = page.tree.selfRect(try id(page, "c"))
        #expect(c.top == f.bottom + 6)
        #expect(c.right == f.right)
    }

    @Test func clearOnOneSideIgnoresFloatsOnTheOther() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="c"></div>"#,
            """
            #f { float: right; width: 100px; height: 80px; }
            #c { clear: left; height: 20px; }
            """
        )
        let body = try bodyRect(page)
        #expect(page.tree.selfRect(try id(page, "c")).top == body.top)
    }

    @Test func clearingBlockMakesItsParentContainTheFloat() throws {
        let page: LayoutTestPage = page(
            #"<div id="wrap"><div id="f"></div><div id="clr"></div></div>"#,
            """
            #f { float: left; width: 100px; height: 80px; }
            #clr { clear: both; }
            """
        )
        #expect(page.tree.height(try id(page, "wrap")) == 80)
    }

    @Test func showingAnEarlierFloatMovesTheClearingBlock() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f" style="display: none"></div></div><div id="c"></div><div id="after"></div>"#,
            """
            #f { float: right; width: 100px; height: 80px; }
            #c { clear: right; height: 20px; }
            #after { height: 10px; }
            """
        )
        let body = try bodyRect(page)
        #expect(page.tree.selfRect(try id(page, "c")).top == body.top)

        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "display", value: "block")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        let fRect: Rect = page.tree.selfRect(try id(page, "f"))
        #expect(page.tree.selfRect(try id(page, "c")).top == fRect.bottom)
        #expect(page.tree.selfRect(try id(page, "after")).top == fRect.bottom + 20)
        expectIncrementalMatchesFull(page)
    }

    @Test func growingAnEarlierFloatMovesTheClearingBlock() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f"></div></div><div id="c"></div>"#,
            """
            #f { float: left; width: 100px; height: 40px; }
            #c { clear: left; height: 20px; }
            """
        )
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "height", value: "90px")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        let fRect: Rect = page.tree.selfRect(try id(page, "f"))
        #expect(fRect.bottom - fRect.top == 90)
        #expect(page.tree.selfRect(try id(page, "c")).top == fRect.bottom)
        expectIncrementalMatchesFull(page)
    }

    @Test func droppingTheFloatPutsTheBoxBackInTheFlow() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="next"></div>"#,
            "#f { float: right; width: 100px; height: 50px; } #next { height: 10px; }"
        )
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "float", value: "none")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        let body = try bodyRect(page)
        let fRect: Rect = page.tree.selfRect(try id(page, "f"))
        #expect(fRect.left == body.left)
        #expect(page.tree.selfRect(try id(page, "next")).top == fRect.bottom)
        expectIncrementalMatchesFull(page)
    }
}
