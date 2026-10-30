import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct HoverTests {

    private func bounds(_ element: Element) throws -> Rect {
        let object: any LayoutObject = try #require(element.layoutObject)
        return object.absoluteBounds()
    }

    private func center(_ rect: Rect) -> CGPoint {
        return CGPoint(x: (rect.left + rect.right) / 2, y: (rect.top + rect.bottom) / 2)
    }

    private func textLayout(of element: Element, in page: LayoutTestPage) throws -> TextLayout {
        let doc: DocumentLayout = try #require(page.frame.document)
        return try #require(
            treeToList(doc).compactMap({ $0 as? TextLayout })
                .first(where: { ($0.node as? TextNode)?.parent === element })
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
        let a: Element = try #require(page.firstElement(id: "a"))
        let b: Element = try #require(page.firstElement(id: "b"))
        let point: CGPoint = center(try bounds(a))

        page.tab.hover(x: point.x, y: point.y)
        page.frame.render()

        #expect(a.isHovered)
        #expect(a.style.isDirty)
        #expect(a.style["color"] == "black")

        page.frame.render()

        #expect(a.style["color"] == "red")
        #expect(b.style["color"] == "black")
        #expect(!a.style.isDirty)
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
        let a: Element = try #require(page.firstElement(id: "a"))
        let b: Element = try #require(page.firstElement(id: "b"))
        let pointA: CGPoint = center(try bounds(a))
        let pointB: CGPoint = center(try bounds(b))

        page.tab.hover(x: pointA.x, y: pointA.y)
        page.frame.render()
        page.frame.render()
        #expect(a.style["color"] == "red")

        page.tab.hover(x: pointB.x, y: pointB.y)
        page.frame.render()
        page.frame.render()

        #expect(!a.isHovered)
        #expect(a.style["color"] == "black")
        #expect(b.isHovered)
        #expect(b.style["color"] == "blue")

        page.tab.clearHover()
        page.frame.render()

        #expect(!b.isHovered)
        #expect(b.style["color"] == "black")
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
        let card: Element = try #require(page.firstElement(id: "card"))
        let label: Element = try #require(page.firstElement(id: "label"))
        let body: Element = try #require(page.firstElement(tag: "body"))
        let point: CGPoint = center(try textLayout(of: label, in: page).absoluteBounds())

        page.tab.hover(x: point.x, y: point.y)
        page.frame.render()
        page.frame.render()

        #expect(card.isHovered)
        #expect(label.isHovered)
        #expect(body.isHovered)
        #expect(label.style["color"] == "purple")
        #expect(card.style["color"] == "black")
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
        let card: Element = try #require(page.firstElement(id: "card"))
        let label: Element = try #require(page.firstElement(id: "label"))
        let after: Element = try #require(page.firstElement(id: "after"))
        let labelPoint: CGPoint = center(try textLayout(of: label, in: page).absoluteBounds())
        let cardPoint: CGPoint = center(try bounds(card))
        let afterPoint: CGPoint = center(try bounds(after))

        page.tab.hover(x: cardPoint.x, y: cardPoint.y)
        page.frame.render()
        page.frame.render()
        #expect(!label.isHovered)
        #expect(label.style["color"] == "red")

        page.tab.hover(x: labelPoint.x, y: labelPoint.y)
        page.frame.render()
        page.frame.render()
        #expect(label.isHovered)
        #expect(label.style["color"] == "red")

        page.tab.hover(x: afterPoint.x, y: afterPoint.y)
        page.frame.render()
        page.frame.render()
        #expect(!card.isHovered)
        #expect(label.style["color"] == "black")
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
        let box: Element = try #require(page.firstElement(id: "box"))
        let before: Rect = try bounds(box)
        let stalePoint: CGPoint = center(before)

        InlineStyle.set(box, property: "margin-top", value: "120px")
        page.frame.setNeedsRender()
        page.tab.hover(x: stalePoint.x, y: stalePoint.y)

        // Style and layout run before the hit test,
        // so the old position is already empty by the time pointer is tested
        page.frame.render()

        let after: Rect = try bounds(box)
        #expect(after.top > before.top + 100)
        #expect(!box.isHovered)

        let fresh: CGPoint = center(after)
        page.tab.hover(x: fresh.x, y: fresh.y)
        page.frame.render()

        #expect(box.isHovered)
    }
}
