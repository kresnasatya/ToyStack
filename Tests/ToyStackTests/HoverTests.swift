import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct HoverTests {

    private func bounds(_ element: ElementRef, in page: LayoutTestPage) throws -> Rect {
        let id: LayoutID = try #require(element.ref.layoutID)
        return page.tree.absoluteBounds(id)
    }

    private func center(_ rect: Rect) -> CGPoint {
        return CGPoint(x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2)
    }

    private func textLayout(of element: ElementRef, in page: LayoutTestPage) throws -> LayoutID {
        let doc: LayoutTree = try #require(page.frame.document)
        let target: NodeID = element.id
        return try #require(
            treeToList(doc, doc.rootID).filter({ doc.isText($0) })
                .first(where: { doc.domRef($0).parent?.id == target })
        )
    }

    @Test func hoverRestylesOnTheRenderAfterTheHitTest() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="a">one</div>
                <div id="b">two</div>
            """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                #a:hover { color: red; }
            """
        )
        let a: ElementRef = try #require(page.firstElement(id: "a"))
        let b: ElementRef = try #require(page.firstElement(id: "b"))
        let point: CGPoint = center(try bounds(a, in: page))

        page.tab.hover(x: point.x, y: point.y)
        page.frame.render()

        #expect(a.isHovered)
        #expect(a.style.isDirty)
        #expect(a.style.computed.text.color == BrowserColor(cssName: "black"))

        page.frame.render()

        #expect(a.style.computed.text.color == BrowserColor(cssName: "red"))
        #expect(b.style.computed.text.color == BrowserColor(cssName: "black"))
        #expect(!a.style.isDirty)
    }

    @Test func ancestorHoverKeepsDescendantLinkTypography() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div class="main"><h1 id="heading">Heading</h1><ul><li><a id="link" href="/x">Link text</a><br>description</li></ul></div>"#,
            rules: """
                html { width: 600px; font-size: 20px; }
                body { display: block; }
                h1, ul, li { display: block; }
                .main li { font-size: 80%; font-style: italic; }
                .main li a { font-size: 125%; font-style: normal; }
                h1:hover { color: #08f; }
                """
        )
        let heading: ElementRef = try #require(page.firstElement(id: "heading"))
        let link: ElementRef = try #require(page.firstElement(id: "link"))
        let headingText: LayoutID = try textLayout(of: heading, in: page)
        let point: CGPoint = center(page.tree.absoluteBounds(headingText))
        let beforeSize: CGFloat = link.style.computed.text.font.size
        let beforeStyle: TextStyle.Style = link.style.computed.text.font.style
        #expect(beforeStyle == .normal)

        page.tab.hover(x: point.x, y: point.y)
        page.frame.render()
        page.frame.render()

        #expect(link.style.computed.text.font.size == beforeSize)
        #expect(link.style.computed.text.font.style == beforeStyle)
    }

    @Test func hoverDoesNotDropLinkTypographyInsideListItem() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div class="main"><ul><li><a id="link" href="/x">Link text</a><br>description</li></ul>"#,
            rules: """
                html { width: 600px; font-size: 20px; }
                body { display: block; }
                ul, li { display: block; }
                body.main li { font-size: 80%; font-style: italic; }
                body.main li a { font-size: 125%; font-style: normal; }
                a:hover { color: #08f; }
                """
        )
        let link: ElementRef = try #require(page.firstElement(id: "link"))
        let textID: LayoutID = try textLayout(of: link, in: page)
        let point: CGPoint = center(page.tree.absoluteBounds(textID))
        let beforeSize: CGFloat = link.style.computed.text.font.size
        let beforeStyle: TextStyle.Style = link.style.computed.text.font.style
        #expect(beforeSize == 20)
        #expect(beforeStyle == .normal)

        page.tab.hover(x: point.x, y: point.y)
        page.frame.render()
        page.frame.render()

        #expect(link.style.computed.text.font.size == beforeSize)
        #expect(link.style.computed.text.font.style == beforeStyle)
    }

    @Test func movingThePointerMovesTheHoverState() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="a">one</div>
                <div id="b">two</div>
            """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                #a:hover { color: red; }
                #b:hover { color: blue; }
            """
        )
        let a: ElementRef = try #require(page.firstElement(id: "a"))
        let b: ElementRef = try #require(page.firstElement(id: "b"))
        let pointA: CGPoint = center(try bounds(a, in: page))
        let pointB: CGPoint = center(try bounds(b, in: page))

        page.tab.hover(x: pointA.x, y: pointA.y)
        page.frame.render()
        page.frame.render()
        #expect(a.style.computed.text.color == BrowserColor(cssName: "red"))

        page.tab.hover(x: pointB.x, y: pointB.y)
        page.frame.render()
        page.frame.render()

        #expect(!a.isHovered)
        #expect(a.style.computed.text.color == BrowserColor(cssName: "black"))
        #expect(b.isHovered)
        #expect(b.style.computed.text.color == BrowserColor(cssName: "blue"))

        page.tab.clearHover()
        page.frame.render()

        #expect(!b.isHovered)
        #expect(b.style.computed.text.color == BrowserColor(cssName: "black"))
    }

    @Test func hoverChainIncludesAncestorsAndRestylesTheirSubtree() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="card"><span id="label">hello</span></div>
            """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                #card:hover span { color: purple; }
            """
        )
        let card: ElementRef = try #require(page.firstElement(id: "card"))
        let label: ElementRef = try #require(page.firstElement(id: "label"))
        let body: ElementRef = try #require(page.firstElement(tag: "body"))
        let labelLayout: LayoutID = try textLayout(of: label, in: page)
        let point: CGPoint = center(page.tree.absoluteBounds(labelLayout))

        page.tab.hover(x: point.x, y: point.y)
        page.frame.render()
        page.frame.render()

        #expect(card.isHovered)
        #expect(label.isHovered)
        #expect(body.isHovered)
        #expect(label.style.computed.text.color == BrowserColor(cssName: "purple"))
        #expect(card.style.computed.text.color == BrowserColor(cssName: "black"))
    }

    @Test func leavingTheAncestorRestoresItsHoverStyledDescendants() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="card">row <span id="label">red</span></div>
                <div id="after">after</div>
            """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                #card:hover span { color: red }
            """
        )
        let card: ElementRef = try #require(page.firstElement(id: "card"))
        let label: ElementRef = try #require(page.firstElement(id: "label"))
        let after: ElementRef = try #require(page.firstElement(id: "after"))
        let labelLayout: LayoutID = try textLayout(of: label, in: page)
        let labelPoint: CGPoint = center(page.tree.absoluteBounds(labelLayout))
        let cardPoint: CGPoint = center(try bounds(card, in: page))
        let afterPoint: CGPoint = center(try bounds(after, in: page))

        page.tab.hover(x: cardPoint.x, y: cardPoint.y)
        page.frame.render()
        page.frame.render()
        #expect(!label.isHovered)
        #expect(label.style.computed.text.color == BrowserColor(cssName: "red"))

        page.tab.hover(x: labelPoint.x, y: labelPoint.y)
        page.frame.render()
        page.frame.render()
        #expect(label.isHovered)
        #expect(label.style.computed.text.color == BrowserColor(cssName: "red"))

        page.tab.hover(x: afterPoint.x, y: afterPoint.y)
        page.frame.render()
        page.frame.render()
        #expect(!card.isHovered)
        #expect(label.style.computed.text.color == BrowserColor(cssName: "black"))
    }

    @Test func hitTestUsesTheLayoutFromTheSameFrame() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box">content</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
            """
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let before: Rect = try bounds(box, in: page)
        let stalePoint: CGPoint = center(before)

        InlineStyle.set(box, property: "margin-top", value: "120px")
        page.frame.setNeedsRender()
        page.tab.hover(x: stalePoint.x, y: stalePoint.y)

        // Style and layout run before the hit test,
        // so the old position is already empty by the time pointer is tested
        page.frame.render()

        let after: Rect = try bounds(box, in: page)
        #expect(after.top > before.top + 100)
        #expect(!box.isHovered)

        let fresh: CGPoint = center(after)
        page.tab.hover(x: fresh.x, y: fresh.y)
        page.frame.render()

        #expect(box.isHovered)
    }
}
