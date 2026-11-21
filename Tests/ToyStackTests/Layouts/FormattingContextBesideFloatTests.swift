import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct FormattingContextBesideFloatTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        """

    private func page(_ html: String, _ rules: String) -> LayoutTestPage {
        return LayoutTestPage(html: html, rules: Self.baseRules + rules)
    }

    private func rect(_ page: LayoutTestPage, _ name: String) throws -> Rect {
        return page.tree.selfRect(try #require(page.firstElement(id: name)?.ref.layoutID))
    }

    private func body(_ page: LayoutTestPage) throws -> Rect {
        return page.tree.contentRect(try #require(page.firstElement(tag: "body")?.ref.layoutID))
    }

    @Test func autoWidthBoxNarrowsBesideALeftFloat() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="b">text</div>"#,
            "#f { float: left; width: 100px; height: 50px; } #b { overflow: hidden; }"
        )
        let f: Rect = try rect(page, "f")
        let b: Rect = try rect(page, "b")
        #expect(b.left == f.right)
        #expect(try b.right == body(page).right)
        #expect(b.top == f.top)
    }

    @Test func autoWidthBoxNarrowsBesideARightFloat() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="b">text</div>"#,
            "#f { float: right; width: 100px; height: 50px; } #b { overflow: hidden; }"
        )
        let b: Rect = try rect(page, "b")
        #expect(try b.left == body(page).left)
        #expect(try b.right == rect(page, "f").left)
    }

    @Test func fixedWidthBoxThatFitsSitsBesideTheFloat() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="b"></div>"#,
            "#f { float: left; width: 100px; height: 50px; } #b { overflow: hidden; width: 300px; height: 10px; }"
        )
        let f: Rect = try rect(page, "f")
        let b: Rect = try rect(page, "b")
        #expect(b.left == f.right)
        #expect(b.top == f.top)
    }

    @Test func fixedWidthBoxTooWideMovesBelowTheFloat() throws {
        let page: LayoutTestPage = page(
            #"<div id="wrap"><div id="f"></div><div id="b"></div></div>"#,
            "#f { float: left; width: 100px; height: 50px; } #b { overflow: hidden; width: 550px; height: 10px; }"
        )
        let f: Rect = try rect(page, "f")
        let b: Rect = try rect(page, "b")
        #expect(b.top == f.bottom)
        #expect(try b.left == body(page).left)
        #expect(try rect(page, "wrap").bottom == b.bottom)
    }

    @Test func ordinaryBlockStillRunsUnderTheFloat() throws {
        let page: LayoutTestPage = page(
            #"<div id="f"></div><div id="b">text</div>"#,
            "#f { float: left; width: 100px; height: 50px; }"
        )
        #expect(try rect(page, "b").left == body(page).left)
    }

    @Test func wideningTheFloatPushesAFixedWidthBoxBelowIt() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f"></div></div><div id="b"></div><div id="after"></div>"#,
            """
            #f { float: left; width: 100px; height: 50px; }
            #b { overflow: hidden; width: 400px; height: 10px; }
            #after { height: 10px; }
            """
        )
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "width", value: "300px")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        let fRect: Rect = try rect(page, "f")
        let b: Rect = try rect(page, "b")
        #expect(b.top == fRect.bottom)
        #expect(try rect(page, "after").top == b.bottom)
        expectIncrementalMatchesFull(page)
    }

    @Test func showingAFloatNarrowsABoxThatWasFullWidth() throws {
        let page: LayoutTestPage = page(
            #"<div id="ad"><div id="f" style="display: none"></div></div><div id="b">text</div>"#,
            "#f { float: right; width: 100px; height: 50px; } #b { overflow: hidden; }"
        )
        let f: ElementRef = try #require(page.firstElement(id: "f"))
        InlineStyle.set(f, property: "display", value: "block")
        page.frame.setNeedsStyle(f.ref)
        page.frame.render()

        #expect(try rect(page, "b").right == rect(page, "f").left)
        expectIncrementalMatchesFull(page)
    }
}
