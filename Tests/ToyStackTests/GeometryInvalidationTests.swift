import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct GeometryInvalidationTests {
    @Test func growingParagraphMovesFollowingParagraph() throws {
        let fixture: ParagraphFixture = makeParagraphFixture()
        let before: BlockLayout = try #require(
            fixture.second.layoutObject as? BlockLayout
        )
        let yBefore: CGFloat = before.y

        let text: TextNode = try #require(fixture.first.children.first as? TextNode)
        text.append(String(repeating: " word", count: 80))

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: BlockLayout = try #require(
            fixture.second.layoutObject as? BlockLayout
        )
        #expect(after.y > yBefore)
    }

    @Test func movingParentDoesNotTranslateAbsoluteChild() throws {
        let fixture: AbsoluteFixture = makeAbsoluteFixture()
        let before: BlockLayout = try #require(
            fixture.absolute.layoutObject as? BlockLayout
        )
        let xBefore: CGFloat = before.x
        let yBefore: CGFloat = before.y

        fixture.header.style["height"] = "80px"

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: BlockLayout = try #require(
            fixture.absolute.layoutObject as? BlockLayout
        )
        #expect(after.x == xBefore)
        #expect(after.y == yBefore)
    }

    @Test func growingNestedListItemMovesFollowingItem() throws {
        let fixture: NestedListFixture = makeNestedListFixture()
        let before: BlockLayout = try #require(
            fixture.secondItem.layoutObject as? BlockLayout
        )
        let yBefore: CGFloat = before.y

        fixture.firstItem.style["height"] = "80px"

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: BlockLayout = try #require(
            fixture.secondItem.layoutObject as? BlockLayout
        )
        #expect(after.y == yBefore + 60)
    }

    @Test func rtlLineStaysRightAlignedAfterPreviousSiblingGrows() throws {
        let fixture: RTLFixture = makeRTLFixture()
        let blockBefore: BlockLayout = try #require(
            fixture.rtl.layoutObject as? BlockLayout
        )
        let yBefore: CGFloat = blockBefore.y
        let textBefore: TextLayout = try #require(
            treeToList(blockBefore).compactMap({ $0 as? TextLayout }).first
        )
        #expect(textBefore.x + textBefore.textWidth == blockBefore.x + blockBefore.width)

        fixture.header.style["height"] = "80px"

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let blockAfter: BlockLayout = try #require(
            fixture.rtl.layoutObject as? BlockLayout
        )
        let textAfter: TextLayout = try #require(
            treeToList(blockAfter).compactMap({ $0 as? TextLayout }).first
        )
        #expect(blockAfter.y == yBefore + 70)
        #expect(textAfter.x + textAfter.textWidth == blockAfter.x + blockAfter.width)
    }
}

// MARK: - Fixtures

@MainActor
private struct ParagraphFixture {
    let tab: BrowserTab
    let html: Element
    let first: Element
    let second: Element

    var frame: Frame { tab.rootFrame }
    var body: Element { html.children[0] as! Element }
}

@MainActor
private func makeParagraphFixture() -> ParagraphFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let html: Element = Element(tag: "html", attributes: [:], parent: nil)
    let body: Element = Element(tag: "body", attributes: [:], parent: html)
    let first: Element = Element(tag: "p", attributes: [:], parent: body)
    let text: TextNode = TextNode(text: "short", parent: first)
    let second: Element = Element(tag: "p", attributes: [:], parent: body)
    let secondText: TextNode = TextNode(text: "after", parent: second)

    html.children = [body]
    body.children = [first, second]
    first.children = [text]
    second.children = [secondText]

    frame.nodes = html
    frame.rules = CSSParser("""
        html { width: 300px; }
        body { display: block; }
        p { display: block; width: 120px; }
        """).parse().rules
    frame.needsStyle = true
    frame.render()
    return ParagraphFixture(tab: tab, html: html, first: first, second: second)
}

@MainActor
private struct AbsoluteFixture {
    let tab: BrowserTab
    let html: Element
    let header: Element
    let absolute: Element

    var frame: Frame { tab.rootFrame }
    var body: Element { html.children[0] as! Element }
}

@MainActor
private func makeAbsoluteFixture() -> AbsoluteFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let html: Element = Element(tag: "html", attributes: [:], parent: nil)
    let body: Element = Element(tag: "body", attributes: [:], parent: html)
    let header: Element = Element(
        tag: "div", attributes: ["class": "header"], parent: body
    )
    let box: Element = Element(tag: "div", attributes: ["class": "box"], parent: body)
    let absolute: Element = Element(
        tag: "div", attributes: ["class": "abs"], parent: box
    )

    html.children = [body]
    body.children = [header, box]
    box.children = [absolute]

    frame.nodes = html
    frame.rules = CSSParser("""
        html { width: 300px; }
        body { display: block; }
        div { display: block; }
        div.header { height: 10px; }
        div.box { width: 200px; }
        div.abs {
            position: absolute;
            left: 20px;
            top: 30px;
            width: 40px;
            height: 40px;
        }
        """).parse().rules
    frame.needsStyle = true
    frame.render()
    return AbsoluteFixture(
        tab: tab, html: html, header: header, absolute: absolute
    )
}

@MainActor
private struct NestedListFixture {
    let tab: BrowserTab
    let html: Element
    let firstItem: Element
    let secondItem: Element

    var frame: Frame { tab.rootFrame }
    var body: Element { html.children[0] as! Element }
    var list: Element { body.children[0] as! Element }
}

@MainActor
private func makeNestedListFixture() -> NestedListFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let html: Element = Element(tag: "html", attributes: [:], parent: nil)
    let body: Element = Element(tag: "body", attributes: [:], parent: html)
    let list: Element = Element(tag: "ul", attributes: [:], parent: body)
    let firstItem: Element = Element(tag: "li", attributes: [:], parent: list)
    let secondItem: Element = Element(tag: "li", attributes: [:], parent: list)
    let firstText: TextNode = TextNode(text: "first", parent: firstItem)
    let secondText: TextNode = TextNode(text: "second", parent: secondItem)

    html.children = [body]
    body.children = [list]
    list.children = [firstItem, secondItem]
    firstItem.children = [firstText]
    secondItem.children = [secondText]

    frame.nodes = html
    frame.rules = CSSParser("""
        html { width: 300px; }
        body { display: block; }
        ul { display: block; }
        li { display: block; height: 20px; }
        """).parse().rules
    frame.needsStyle = true
    frame.render()
    return NestedListFixture(
        tab: tab, html: html, firstItem: firstItem, secondItem: secondItem
    )
}

@MainActor
private struct RTLFixture {
    let tab: BrowserTab
    let html: Element
    let header: Element
    let rtl: Element

    var frame: Frame { tab.rootFrame }
    var body: Element { html.children[0] as! Element }
}

@MainActor
private func makeRTLFixture() -> RTLFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let html: Element = Element(tag: "html", attributes: [:], parent: nil)
    let body: Element = Element(tag: "body", attributes: [:], parent: html)
    let header: Element = Element(
        tag: "div", attributes: ["class": "header"], parent: body
    )
    let rtl: Element = Element(
        tag: "div",
        attributes: ["class": "rtl", "dir": "rtl"],
        parent: body
    )
    let text: TextNode = TextNode(text: "hello", parent: rtl)

    html.children = [body]
    body.children = [header, rtl]
    rtl.children = [text]

    frame.nodes = html
    frame.rules = CSSParser("""
        html { width: 300px; }
        body { display: block; }
        div { display: block; }
        div.header { height: 10px; }
        div.rtl { width: 200px; }
        """).parse().rules
    frame.needsStyle = true
    frame.render()
    return RTLFixture(tab: tab, html: html, header: header, rtl: rtl)
}
