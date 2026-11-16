import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct BoxSizingLayoutTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        """

    private func outerSize(_ page: LayoutTestPage, _ box: LayoutID) -> CGSize {
        let rect: Rect = page.tree.selfRect(box)
        return CGSize(width: rect.right - rect.left, height: rect.bottom - rect.top)
    }

    @Test func borderBoxWidthAndHeightIncludePaddingAndBorder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { box-sizing: border-box; width: 200px; height: 100px;
                       padding: 10px; border: 5px solid black; }
                """
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)

        #expect(page.tree.width(box) == 170)
        #expect(page.tree.height(box) == 70)
        #expect(outerSize(page, box) == CGSize(width: 200, height: 100))
    }

    @Test func contentBoxAddsPaddingAndBorderOutsideTheSize() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="implicit"></div><div id="explicit"></div>"#,
            rules: Self.baseRules + """
                div { width: 200px; height: 100px; padding: 10px; border: 5px solid black; }
                #explicit { box-sizing: content-box; }
                """
        )
        for id in ["implicit", "explicit"] {
            let box: LayoutID = try #require(page.firstElement(id: id)?.ref.layoutID)
            #expect(page.tree.width(box) == 200)
            #expect(outerSize(page, box) == CGSize(width: 230, height: 130))
        }
    }

    @Test func borderBoxHeightDecidesWhereTheNextSiblingStarts() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="a"></div><div id="b"></div>"#,
            rules: Self.baseRules + """
                #a { box-sizing: border-box; height: 50px; padding: 8px; border: 2px solid black; }
                """
        )
        let a: LayoutID = try #require(page.firstElement(id: "a")?.ref.layoutID)
        let b: LayoutID = try #require(page.firstElement(id: "b")?.ref.layoutID)

        #expect(page.tree.selfRect(b).top == page.tree.selfRect(a).top + 50)
    }

    @Test func borderBoxContentNeverShrinksBelowZero() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { box-sizing: border-box; width: 10px; height: 10px; padding: 20px; }
                """
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)

        #expect(page.tree.width(box) == 0)
        #expect(page.tree.height(box) == 0)
        #expect(outerSize(page, box) == CGSize(width: 40, height: 40))
    }

    @Test func borderBoxSubtractsOnlyTheSidesOfEachAxis() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { box-sizing: border-box; width: 200px; height: 50px;
                       border-left: 10px solid black; border-top: 4px solid black; }
                """
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)

        #expect(page.tree.width(box) == 190)
        #expect(page.tree.height(box) == 46)
        #expect(outerSize(page, box) == CGSize(width: 200, height: 50))
    }

    @Test func borderBoxWithoutAWidthStillFillsTheParent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { box-sizing: border-box; padding: 10px; border: 5px solid black; }
                """
        )
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)

        #expect(page.tree.width(box) == 570)
        #expect(outerSize(page, box).width == 600)
    }

    @Test func switchingToBorderBoxRelayoutsIncrementally() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="a"></div><div id="b"></div>"#,
            rules: Self.baseRules + """
                #a { width: 200px; height: 100px; padding: 10px; border: 5px solid black; }
                """
        )
        let a: ElementRef = try #require(page.firstElement(id: "a"))

        InlineStyle.set(a, property: "box-sizing", value: "border-box")
        page.frame.setNeedsRender()
        page.frame.render()

        let aBox: LayoutID = try #require(a.ref.layoutID)
        let bBox: LayoutID = try #require(page.firstElement(id: "b")?.ref.layoutID)
        #expect(page.tree.width(aBox) == 170)
        #expect(page.tree.height(aBox) == 70)
        #expect(page.tree.selfRect(bBox).top == page.tree.selfRect(aBox).bottom)

        let document: LayoutTree = try #require(page.frame.document)
        expectAllLayoutFieldsClean(document)
        expectIncrementalMatchesFull(page)
    }

    @Test func paddingChangeInsideABorderBoxKeepsItsOuterSize() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { box-sizing: border-box; width: 200px; height: 100px; }
                """
        )
        let element: ElementRef = try #require(page.firstElement(id: "box"))

        InlineStyle.set(element, property: "padding", value: "20px")
        InlineStyle.set(element, property: "border", value: "5px solid black")
        page.frame.setNeedsRender()
        page.frame.render()

        let box: LayoutID = try #require(element.ref.layoutID)
        #expect(page.tree.width(box) == 150)
        #expect(page.tree.height(box) == 50)
        #expect(outerSize(page, box) == CGSize(width: 200, height: 100))
        expectIncrementalMatchesFull(page)
    }
}
