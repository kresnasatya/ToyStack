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
        let box: ElementRef = try #require(page.firstElement(tag: "div"))
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
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let text: TextRef = try #require(p.children.first?.text)
        let block: LayoutRef = try #require(page.firstBlock(in: p))
        let textLayout: LayoutRef = try #require(treeToList(block).first(where: { $0.isText }))
        let normal: BrowserFont = getFont(size: 16, weight: "normal", style: "roman")

        p.style.mutate { $0.text.font.size = 32 }

        let grown: BrowserFont = fontForElement(text.ref, zoom: 1, notify: textLayout.fontField)
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
        let first: ElementRef = try #require(page.firstElement(tag: "div"))
        let body: ElementRef = try #require(page.firstElement(tag: "body"))
        let second: ElementRef = try #require(
            treeToList(page.frame.nodes)
                .compactMap({ $0.element })
                .first(where: { $0.attributes["id"] == "second" })
        )

        let firstBefore: LayoutRef = try #require(page.ref(of: first).layout)
        let secondBefore: LayoutRef = try #require(page.ref(of: second).layout)
        let bodyBefore: LayoutRef = try #require(page.ref(of: body).layout)
        let secondYBefore: CGFloat = secondBefore.y
        let bodyHeightBefore: CGFloat = bodyBefore.height

        InlineStyle.set(first, property: "margin-bottom", value: "0px")
        page.frame.setNeedsRender()
        page.frame.render()

        let firstAfter: LayoutRef = try #require(page.ref(of: first).layout)
        let secondAfter: LayoutRef = try #require(page.ref(of: second).layout)
        let bodyAfter: LayoutRef = try #require(page.ref(of: body).layout)

        #expect(firstAfter.id == firstBefore.id)
        #expect(secondAfter.id == secondBefore.id)
        #expect(bodyAfter.id == bodyBefore.id)
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
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutRef = try #require(page.firstBlock(in: p))
        let text: LayoutRef = try #require(
            treeToList(block).first(where: { $0.isText })
        )

        p.style.mutate { $0.text.font.size = 32 }

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
        let a: ElementRef = try #require(treeToList(page.frame.nodes).compactMap({ $0.element }).first(where: { $0.attributes["id"] == "a" }))
        let b: ElementRef = try #require(treeToList(page.frame.nodes).compactMap({ $0.element }).first(where: { $0.attributes["id"] == "b" }))
        let aBefore: LayoutRef = try #require(page.firstEmbed(in: a))
        let bBefore: LayoutRef = try #require(page.firstEmbed(in: b))
        let aHeightBefore: CGFloat = aBefore.height
        let bHeightBefore: CGFloat = bBefore.height

        page.frame.focusElement(a)
        page.frame.render()

        let aAfter: LayoutRef = try #require(page.firstEmbed(in: a))
        let bAfter: LayoutRef = try #require(page.firstEmbed(in: b))

        #expect(aAfter.height > aHeightBefore)
        #expect(bAfter.height == bHeightBefore)
        #expect(bAfter.id == bBefore.id)
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
        let p: ElementRef = try #require(page.firstElement(tag: "p"))

        page.tab.forcedColors = true
        page.frame.render()

        #expect(usesForcedColors(p.ref))
        #expect(p.style.computed.text.color == BrowserColor(cssName: ForcedColor.canvasText))
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
        let p: ElementRef = try #require(page.firstElement(tag: "p"))

        page.frame.focusElement(p)
        page.frame.render()

        for node in treeToList(page.frame.nodes) {
            #expect(!node.style.isDirty)
        }
    }

    @Test func stylePhaseSkipsCleanSubtrees() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="left"><p id="target">one</p></div>
                <div id="right"><p id="clean">two</p></div>
                """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div, p { display: block; }
                #target { color: blue; }
                """
        )
        let target: ElementRef = try #require(page.firstElement(id: "target"))
        let clean: ElementRef = try #require(page.firstElement(id: "clean"))

        // The cascade inherits black here. If the clean subtree is visited,
        // applyNodeStyle overwrites this value.
        clean.style.mutate { $0.text.color = BrowserColor(cssName: "red") }

        page.frame.setNeedsStyle(target.ref)
        #expect(page.frame.nodes.style.hasDirtyDescendant)
        page.frame.render()

        #expect(target.style.computed.text.color == BrowserColor(cssName: "blue"))
        #expect(clean.style.computed.text.color == BrowserColor(cssName: "red"))
        #expect(!clean.style.hasDirtyDescendant)

        for node in treeToList(page.frame.nodes) {
            #expect(!node.style.hasDirtyDescendant)
        }
    }

    @Test func focusRestylesDescendantsThatMatchAFocusSeelctor() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="box">
                    <p id="child">text</p>
                </div>
            """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                p { display: block; color: black; }
                div:focus p { color: purple; }
            """
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let child: ElementRef = try #require(page.firstElement(id: "child"))

        page.frame.focusElement(box)
        page.frame.render()

        #expect(child.style.computed.text.color == BrowserColor(cssName: "purple"))
    }
}
