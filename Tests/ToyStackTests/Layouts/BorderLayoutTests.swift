import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct BorderLayoutTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        """

    @Test func borderInsetsChildrenAndWidensTheBox() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="inner"></div></div>"#,
            rules: Self.baseRules + "#outer { padding: 10px; border: 5px solid black; }"
        )
        let outer: LayoutID = try #require(page.firstElement(id: "outer")?.ref.layoutID)
        let inner: LayoutID = try #require(page.firstElement(id: "inner")?.ref.layoutID)
        let body: LayoutID = try #require(page.firstElement(tag: "body")?.ref.layoutID)
        let box: Rect = page.tree.selfRect(outer)

        #expect(page.tree.width(outer) == 570)
        #expect(box.right - box.left == 600)
        #expect(box.left == page.tree.x(body))
        #expect(box.top == page.tree.y(body))
        #expect(page.tree.x(outer) == box.left + 15)
        #expect(page.tree.y(outer) == box.top + 15)
        #expect(page.tree.x(inner) == page.tree.x(outer))
    }

    @Test func borderPushesTheNextSiblingDown() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="a"></div><div id="b"></div>"#,
            rules: Self.baseRules + """
                div { height: 10px; }
                #a { border: 4px solid black; }
                """
        )
        let a: LayoutID = try #require(page.firstElement(id: "a")?.ref.layoutID)
        let b: LayoutID = try #require(page.firstElement(id: "b")?.ref.layoutID)

        #expect(page.tree.selfRect(a).bottom - page.tree.selfRect(a).top == 18)
        #expect(page.tree.selfRect(b).top == page.tree.selfRect(a).bottom)
    }

    @Test func parentHeightIncludesChildBorders() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="inner"></div></div>"#,
            rules: Self.baseRules + "#inner { height: 10px; border: 3px solid black; }"
        )
        let outer: LayoutID = try #require(page.firstElement(id: "outer")?.ref.layoutID)

        #expect(page.tree.height(outer) == 16)
    }

    @Test func borderWithoutAStyleTakesNoSpace() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { border-width: 10px; }
                #box { border-color: red; }
                """
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)

        #expect(page.tree.width(box) == 600)
        #expect(page.tree.selfRect(box).left == page.tree.x(box))
    }

    @Test func hiddenBorderTakesNoSpace() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { border: 10px hidden black; }"
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)

        #expect(page.tree.width(box) == 600)
    }

    @Test func borderScalesWithZoom() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { zoom: 2; border: 3px solid black; }"
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)

        #expect(page.tree.x(box) - page.tree.selfRect(box).left == 6)
        #expect(page.tree.width(box) == 588)
    }

    @Test func borderIsClickable() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { height: 20px; border: 8px solid black; }"
        )
        let element: ElementRef = try #require(page.firstElement(id: "box"))
        let box: LayoutID = try #require(element.ref.layoutID)
        let rect: Rect = page.tree.selfRect(box)

        #expect(page.tree.hitTest(box, x: rect.left + 2, y: rect.top + 2)?.dom == element.id)
    }

    @Test func eachSideTakesItsOwnWidth() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div><div id="next"></div>"#,
            rules: Self.baseRules + """
                #box { height: 20px; border-style: solid; border-width: 1px 2px 3px 4px; }
                """
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let next: LayoutID = try #require(page.firstElement(id: "next")?.ref.layoutID)
        let rect: Rect = page.tree.selfRect(box)

        #expect(page.tree.x(box) - rect.left == 4)
        #expect(page.tree.y(box) - rect.top == 1)
        #expect(rect.right - (page.tree.x(box) + page.tree.width(box)) == 2)
        #expect(rect.bottom - (page.tree.y(box) + page.tree.height(box)) == 3)
        #expect(page.tree.width(box) == 594)
        #expect(page.tree.selfRect(next).top == rect.bottom)
    }

    @Test func borderOnOneSideLeavesTheOtherSidesEmpty() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div><div id="next"></div>"#,
            rules: Self.baseRules + "#box { height: 20px; border-bottom: 2px solid gray; }"
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let next: LayoutID = try #require(page.firstElement(id: "next")?.ref.layoutID)
        let rect: Rect = page.tree.selfRect(box)

        #expect(page.tree.width(box) == 600)
        #expect(rect.left == page.tree.x(box))
        #expect(rect.top == page.tree.y(box))
        #expect(page.tree.selfRect(next).top == rect.top + 22)
    }

    @Test func oneSideChangeRelayoutsIncrementally() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="a"></div><div id="b"></div>"#,
            rules: Self.baseRules + "#a, #b { height: 10px; } #a { border: 1px solid black; }"
        )
        let a: ElementRef = try #require(page.firstElement(id: "a"))

        InlineStyle.set(a, property: "border-left-width", value: "9px")
        InlineStyle.set(a, property: "border-bottom-style", value: "none")
        page.frame.setNeedsRender()
        page.frame.render()

        let aBox: LayoutID = try #require(a.ref.layoutID)
        let bBox: LayoutID = try #require(page.firstElement(id: "b")?.ref.layoutID)
        #expect(page.tree.width(aBox) == 590)
        #expect(page.tree.selfRect(aBox).bottom == page.tree.y(aBox) + 10)
        #expect(page.tree.selfRect(bBox).top == page.tree.selfRect(aBox).bottom)
        expectIncrementalMatchesFull(page)
    }

    @Test func borderChangeRelayoutsIncrementally() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="a"></div><div id="b"></div></div>"#,
            rules: Self.baseRules + "#a, #b { height: 10px; }"
        )
        let a: ElementRef = try #require(page.firstElement(id: "a"))

        InlineStyle.set(a, property: "border", value: "6px solid black")
        page.frame.setNeedsRender()
        page.frame.render()

        let outer: LayoutID = try #require(page.firstElement(id: "outer")?.ref.layoutID)
        let aBox: LayoutID = try #require(a.ref.layoutID)
        let bBox: LayoutID = try #require(page.firstElement(id: "b")?.ref.layoutID)
        #expect(page.tree.width(aBox) == 588)
        #expect(page.tree.selfRect(bBox).top == page.tree.selfRect(aBox).bottom)
        #expect(page.tree.height(outer) == 32)

        let document: LayoutTree = try #require(page.frame.document)
        expectAllLayoutFieldsClean(document)
        expectIncrementalMatchesFull(page)
    }

    @Test func borderStyleChangeAloneRelayouts() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="a"></div><div id="b"></div>"#,
            rules: Self.baseRules + "#a, #b { height: 10px; } #a { border-width: 5px; }"
        )
        let a: ElementRef = try #require(page.firstElement(id: "a"))

        InlineStyle.set(a, property: "border-style", value: "solid")
        page.frame.setNeedsRender()
        page.frame.render()

        let aBox: LayoutID = try #require(a.ref.layoutID)
        let bBox: LayoutID = try #require(page.firstElement(id: "b")?.ref.layoutID)
        #expect(page.tree.width(aBox) == 590)
        #expect(page.tree.selfRect(bBox).top == page.tree.selfRect(aBox).bottom)
        expectIncrementalMatchesFull(page)
    }
}
