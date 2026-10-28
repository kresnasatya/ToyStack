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
        let outer: Element = try #require(page.firstElement(tag: "div"))
        let inner: Element = try #require(outer.children.first as? Element)
        let outerBox: BlockLayout = try #require(outer.layoutObject as? BlockLayout)
        let innerBox: BlockLayout = try #require(inner.layoutObject as? BlockLayout)

        #expect(outerBox.width == 580)
        #expect(outerBox.selfRect().right - outerBox.selfRect().left == 600)
        #expect(innerBox.x == outerBox.x)
        #expect(innerBox.y == outerBox.y)
        #expect(outerBox.selfRect().left == outerBox.x - 10)
        #expect(outerBox.selfRect().top == outerBox.y - 10)
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
        let elements: [Element] = treeToList(page.frame.nodes).compactMap {
            $0 as? Element
        }
        let a: Element = try #require(elements.first { $0.attributes["id"] == "a" })
        let b: Element = try #require(elements.first { $0.attributes["id"] == "b" })
        let aBox: BlockLayout = try #require(a.layoutObject as? BlockLayout)
        let bBox: BlockLayout = try #require(b.layoutObject as? BlockLayout)

        #expect(aBox.selfRect().bottom - aBox.selfRect().top == 22)
        #expect(bBox.y == aBox.y + aBox.height + 12)
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
        let box: Element = try #require(page.firstElement(tag: "div"))

        InlineStyle.set(box, property: "padding", value: "20px")
        page.frame.setNeedsRender()
        page.frame.render()

        let boxLayout: BlockLayout = try #require(box.layoutObject as? BlockLayout)
        #expect(boxLayout.width == 560)
        #expect(boxLayout.selfRect().right - boxLayout.selfRect().left == 600)
        #expect(boxLayout.selfRect().left == boxLayout.x - 20)

        let document: DocumentLayout = try #require(page.frame.document)
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
        let box: Element = try #require(page.firstElement(tag: "div"))
        let layout: BlockLayout = try #require(box.layoutObject as? BlockLayout)

        #expect(layout.hitTest(x: layout.x - 5, y: layout.y + 5)?.node === box)
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
        let box: Element = try #require(page.firstElement(tag: "div"))
        page.frame.setNeedsPaint()
        page.frame.paint()

        let layout: BlockLayout = try #require(box.layoutObject as? BlockLayout)
        let rects: [Rect] = page.frame.displayList.compactMap {
            ($0 as? DrawRect)?.rect
        }
        #expect(rects.contains(layout.selfRect()))
    }
}
