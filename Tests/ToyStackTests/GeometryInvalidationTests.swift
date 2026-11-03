import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct GeometryInvalidationTests {
    @Test func growingParagraphMovesFollowingParagraph() throws {
        let fixture: ParagraphFixture = makeParagraphFixture()
        let before: LayoutRef = try #require(
            fixture.second.ref.layout
        )
        let yBefore: CGFloat = before.y

        let text: TextRef = try #require(fixture.first.children.first?.text)
        text.append(String(repeating: " word", count: 80))

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: LayoutRef = try #require(
            fixture.second.ref.layout
        )
        #expect(after.y > yBefore)
    }

    @Test func movingParentDoesNotTranslateAbsoluteChild() throws {
        let fixture: AbsoluteFixture = makeAbsoluteFixture()
        let before: LayoutRef = try #require(
            fixture.absolute.ref.layout
        )
        let xBefore: CGFloat = before.x
        let yBefore: CGFloat = before.y

        InlineStyle.set(fixture.header, property: "height", value: "80px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: LayoutRef = try #require(
            fixture.absolute.ref.layout
        )
        #expect(after.x == xBefore)
        #expect(after.y == yBefore)
    }

    @Test func growingNestedListItemMovesFollowingItem() throws {
        let fixture: NestedListFixture = makeNestedListFixture()
        let before: LayoutRef = try #require(
            fixture.secondItem.ref.layout
        )
        let yBefore: CGFloat = before.y

        InlineStyle.set(fixture.firstItem, property: "height", value: "80px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: LayoutRef = try #require(
            fixture.secondItem.ref.layout
        )
        #expect(after.y == yBefore + 60)
    }

    @Test func rtlLineStaysRightAlignedAfterPreviousSiblingGrows() throws {
        let fixture: RTLFixture = makeRTLFixture()
        let blockBefore: LayoutRef = try #require(
            fixture.rtl.ref.layout
        )
        let yBefore: CGFloat = blockBefore.y
        let textBefore: LayoutRef = try #require(
            treeToList(blockBefore).first(where: { $0.isText })
        )
        #expect(textBefore.x + textBefore.textData.metrics.width == blockBefore.x + blockBefore.width)

        InlineStyle.set(fixture.header, property: "height", value: "80px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let blockAfter: LayoutRef = try #require(
            fixture.rtl.ref.layout
        )
        let textAfter: LayoutRef = try #require(
            treeToList(blockAfter).first(where: { $0.isText })
        )
        #expect(blockAfter.y == yBefore + 70)
        #expect(textAfter.x + textAfter.textData.metrics.width == blockAfter.x + blockAfter.width)
    }
}

// MARK: - Fixtures

@MainActor
private func element(_ id: String, in dom: DOMTree) -> ElementRef {
    guard let ref: ElementRef = treeToList(dom.ref(dom.root))
        .compactMap({ $0.element })
        .first(where: { $0.attributes["id"] == id })
    else {
        preconditionFailure("missing element \(id)")
    }
    return ref
}

@MainActor
private func element(_ tag: String, _ className: String?, in dom: DOMTree) -> ElementRef {
    guard let ref: ElementRef = treeToList(dom.ref(dom.root))
        .compactMap({ $0.element })
        .first(where: {
            $0.tag == tag && (className == nil || $0.attributes["class"] == className)
        })
    else {
        preconditionFailure("missing element \(tag).\(className ?? "")")
    }
    return ref
}

@MainActor
private struct ParagraphFixture {
    let tab: BrowserTab
    let first: ElementRef
    let second: ElementRef

    var frame: Frame { tab.rootFrame }
}

@MainActor
private func makeParagraphFixture() -> ParagraphFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let dom: DOMTree = HTMLParser(
        body: #"<p id="first">short</p><p id="second">after</p>"#
    ).parse()

    frame.replaceDOM(dom)
    frame.setStyleRules(CSSParser("""
        html { width: 300px; }
        body { display: block; }
        p { display: block; width: 120px; }
        """).parse().rules)
    frame.setNeedsRender()
    frame.render()
    return ParagraphFixture(
        tab: tab,
        first: element("first", in: dom),
        second: element("second", in: dom)
    )
}

@MainActor
private struct AbsoluteFixture {
    let tab: BrowserTab
    let header: ElementRef
    let absolute: ElementRef

    var frame: Frame { tab.rootFrame }
}

@MainActor
private func makeAbsoluteFixture() -> AbsoluteFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let dom: DOMTree = HTMLParser(
        body: #"<div class="header"></div><div class="box"><div class="abs"></div></div>"#
    ).parse()

    frame.replaceDOM(dom)
    frame.setStyleRules(CSSParser("""
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
        """).parse().rules)
    frame.setNeedsRender()
    frame.render()
    return AbsoluteFixture(
        tab: tab,
        header: element("div", "header", in: dom),
        absolute: element("div", "abs", in: dom)
    )
}

@MainActor
private struct NestedListFixture {
    let tab: BrowserTab
    let firstItem: ElementRef
    let secondItem: ElementRef

    var frame: Frame { tab.rootFrame }
}

@MainActor
private func makeNestedListFixture() -> NestedListFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let dom: DOMTree = HTMLParser(
        body: #"<ul><li id="first">first</li><li id="second">second</li></ul>"#
    ).parse()

    frame.replaceDOM(dom)
    frame.setStyleRules(CSSParser("""
        html { width: 300px; }
        body { display: block; }
        ul { display: block; }
        li { display: block; height: 20px; }
        """).parse().rules)
    frame.setNeedsRender()
    frame.render()
    return NestedListFixture(
        tab: tab,
        firstItem: element("first", in: dom),
        secondItem: element("second", in: dom)
    )
}

@MainActor
private struct RTLFixture {
    let tab: BrowserTab
    let header: ElementRef
    let rtl: ElementRef

    var frame: Frame { tab.rootFrame }
}

@MainActor
private func makeRTLFixture() -> RTLFixture {
    let tab: BrowserTab = BrowserTab(tabHeight: 600, tabWidth: 400)
    let frame: Frame = tab.rootFrame
    let dom: DOMTree = HTMLParser(
        body: #"<div class="header"></div><div class="rtl" dir="rtl">hello</div>"#
    ).parse()

    frame.replaceDOM(dom)
    frame.setStyleRules(CSSParser("""
        html { width: 300px; }
        body { display: block; }
        div { display: block; }
        div.header { height: 10px; }
        div.rtl { width: 200px; }
        """).parse().rules)
    frame.setNeedsRender()
    frame.render()
    return RTLFixture(
        tab: tab,
        header: element("div", "header", in: dom),
        rtl: element("div", "rtl", in: dom)
    )
}
