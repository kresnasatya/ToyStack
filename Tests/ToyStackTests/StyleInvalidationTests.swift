import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleInvalidationTests {

    @Test func styleObjectIsNotReplaced() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">text</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                """
        )
        let box: Element = try #require(page.firstElement(tag: "div"))
        let fields: StyleFields = box.style

        InlineStyle.set(box, property: "width", value: "120px")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(box.style === fields)
    }

    @Test func fontResolutionReadsTheParentElement() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">hello</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; width: 300px; }
                """
        )
        let p: Element = try #require(page.firstElement(tag: "p"))
        let text: TextNode = try #require(p.children.first as? TextNode)
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        let textLayout: TextLayout = try #require(treeToList(block).compactMap({ $0 as? TextLayout }).first)
        let normal: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")

        p.style["font-size"] = "32px"

        let grown: BrowserFont = fontForElement(text, zoom: 1, notify: textLayout.fontField)
        #expect(grown.linespace > normal.linespace)
    }

    @Test func marginBottomChangeMovesNextSiblingWithoutRebuildingChildren() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="first">one</div><div id="second">two</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; margin-bottom: 50px; }
                """
        )
        let first: Element = try #require(page.firstElement(tag: "div"))
        let body: Element = try #require(page.firstElement(tag: "body"))
        let second: Element = try #require(
            treeToList(page.frame.nodes)
                .compactMap({ $0 as? Element })
                .first(where: { $0.attributes["id"] == "second" })
        )

        let firstBefore: any LayoutObject = try #require(first.layoutObject)
        let secondBefore: any LayoutObject = try #require(second.layoutObject)
        let bodyBefore: any LayoutObject = try #require(body.layoutObject)
        let secondYBefore: CGFloat = secondBefore.y
        let bodyHeightBefore: CGFloat = bodyBefore.height

        InlineStyle.set(first, property: "margin-bottom", value: "0px")
        page.frame.setNeedsRender()
        page.frame.render()

        let firstAfter: any LayoutObject = try #require(first.layoutObject)
        let secondAfter: any LayoutObject = try #require(second.layoutObject)
        let bodyAfter: any LayoutObject = try #require(body.layoutObject)

        #expect(firstAfter === firstBefore)
        #expect(secondAfter === secondBefore)
        #expect(bodyAfter === bodyBefore)
        #expect(secondAfter.y == secondYBefore - 50)
        #expect(bodyAfter.height == bodyHeightBefore - 50)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
    }

    @Test func textFontFieldDependsOnTheParentElement() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">hello</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; width: 300px; }
                """
        )
        let p: Element = try #require(page.firstElement(tag: "p"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        let text: TextLayout = try #require(
            treeToList(block).compactMap({ $0 as? TextLayout }).first
        )

        p.style["font-size"] = "32px"

        #expect(text.fontField.dirty)
    }

    @Test func focusChangeRestylesOnlyTheFocusedNode() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <p><input id="b" type="text"></p>
                <p><input id="a" type="text"></p>
            """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; }
                input:focus { font-size: 32px; }
            """
        )
        let a: Element = try #require(treeToList(page.frame.nodes).compactMap({ $0 as? Element }).first(where: { $0.attributes["id"] == "a" }))
        let b: Element = try #require(treeToList(page.frame.nodes).compactMap({ $0 as? Element }).first(where: { $0.attributes["id"] == "b" }))
        let aBefore: InputLayout = try #require(page.firstLayout(InputLayout.self, in: a))
        let bBefore: InputLayout = try #require(page.firstLayout(InputLayout.self, in: b))
        let aHeightBefore: CGFloat = aBefore.height
        let bHeightBefore: CGFloat = bBefore.height

        page.frame.focusElement(a)
        page.frame.render()

        let aAfter: InputLayout = try #require(page.firstLayout(InputLayout.self, in: a))
        let bAfter: InputLayout = try #require(page.firstLayout(InputLayout.self, in: b))

        #expect(aAfter.height > aHeightBefore)
        #expect(bAfter.height == bHeightBefore)
        #expect(bAfter === bBefore)
        #expect(!a.style.isDirty)
        #expect(!b.style.isDirty)
    }

    @Test func forcedColorsRestylesTextWithoutLayout() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">hello</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(tag: "p"))

        page.tab.forcedColors = true
        page.frame.render()

        #expect(usesForcedColors(p))
        #expect(p.style["color"] == ForcedColor.canvasText)
        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 0)
    }

    @Test func noDirtyStyleFieldsAfterRender() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="p">hello</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(tag: "p"))

        page.frame.focusElement(p)
        page.frame.render()

        for node in treeToList(page.frame.nodes) {
            #expect(!node.style.isDirty)
        }
    }
}
