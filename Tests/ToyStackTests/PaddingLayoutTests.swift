import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct PaddingLayoutTests {
    @Test func paddingInsetsChildrenAndExtendsTheBox() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="outer"><div id="inner"></div></div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                #outer { padding: 10px; }
                """
        )
        let outer: ElementRef = try #require(page.firstElement(tag: "div"))
        let inner: ElementRef = try #require(outer.children.first?.element)
        let outerBox: LayoutID = try #require(page.ref(of: outer).layoutID)
        let innerBox: LayoutID = try #require(page.ref(of: inner).layoutID)

        #expect(page.tree.width(outerBox) == 580)
        #expect(page.tree.selfRect(outerBox).right - page.tree.selfRect(outerBox).left == 600)
        #expect(page.tree.x(innerBox) == page.tree.x(outerBox))
        #expect(page.tree.y(innerBox) == page.tree.y(outerBox))
        #expect(page.tree.selfRect(outerBox).left == page.tree.x(outerBox) - 10)
        #expect(page.tree.selfRect(outerBox).top == page.tree.y(outerBox) - 10)
    }

    @Test func paddingBottomSeparatesSiblings() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="a"></div><div id="b"></div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; height: 10px; }
                #a { padding-bottom: 12px; }
                """
        )
        let elements: [ElementRef] = treeToList(page.frame.nodes).compactMap {
            $0.element
        }
        let a: ElementRef = try #require(elements.first { $0.attributes["id"] == "a" })
        let b: ElementRef = try #require(elements.first { $0.attributes["id"] == "b" })
        let aBox: LayoutID = try #require(page.ref(of: a).layoutID)
        let bBox: LayoutID = try #require(page.ref(of: b).layoutID)

        #expect(page.tree.selfRect(aBox).bottom - page.tree.selfRect(aBox).top == 22)
        #expect(page.tree.y(bBox) == page.tree.y(aBox) + page.tree.height(aBox) + 12)
    }

    @Test func paddingChangeRelayoutsIncrementally() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div id="child"></div></div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                """
        )
        let box: ElementRef = try #require(page.firstElement(tag: "div"))

        InlineStyle.set(box, property: "padding", value: "20px")
        page.frame.setNeedsRender()
        page.frame.render()

        let boxLayout: LayoutID = try #require(page.ref(of: box).layoutID)
        #expect(page.tree.width(boxLayout) == 560)
        #expect(page.tree.selfRect(boxLayout).right - page.tree.selfRect(boxLayout).left == 600)
        #expect(page.tree.selfRect(boxLayout).left == page.tree.x(boxLayout) - 20)

        var document: LayoutTree = try #require(page.frame.document)
        expectAllLayoutFieldsClean(document)
        expectIncrementalMatchesFull(page)
    }

    @Test func paddingIsClickable() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; height: 20px; }
                #box { padding: 10px; }
                """
        )
        let box: ElementRef = try #require(page.firstElement(tag: "div"))
        let layout: LayoutID = try #require(page.ref(of: box).layoutID)

        #expect(page.tree.hitTest(layout, x: page.tree.x(layout) - 5, y: page.tree.y(layout) + 5)?.dom == box.id)
    }

    @Test func backgroundCoversPadding() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; height: 20px; }
                #box { padding: 10px; background-color: gold; }
                """
        )
        let box: ElementRef = try #require(page.firstElement(tag: "div"))
        page.frame.setNeedsPaint()
        page.frame.paint()

        let layout: LayoutID = try #require(page.ref(of: box).layoutID)
        let rects: [Rect] = page.frame.displayList.compactMap { op -> Rect? in
            guard case .rect(let rect, _) = op else { return nil }
            return rect
        }
        #expect(rects.contains(page.tree.selfRect(layout)))
    }
}
