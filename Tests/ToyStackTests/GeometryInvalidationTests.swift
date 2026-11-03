import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct GeometryInvalidationTests {
    @Test func growingParagraphMovesFollowingParagraph() throws {
        let fixture: ParagraphFixture = makeParagraphFixture()
        var tree: LayoutTree = fixture.tree
        let before: LayoutID = try #require(fixture.second.ref.layoutID)
        let yBefore: CGFloat = tree.y(before)

        let text: TextRef = try #require(fixture.first.children.first?.text)
        text.append(String(repeating: " word", count: 80))

        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: LayoutID = try #require(fixture.second.ref.layoutID)
        #expect(fixture.tree.y(after) > yBefore)
    }

    @Test func movingParentDoesNotTranslateAbsoluteChild() throws {
        let fixture: AbsoluteFixture = makeAbsoluteFixture()
        var tree: LayoutTree = fixture.tree
        let before: LayoutID = try #require(fixture.absolute.ref.layoutID)
        let xBefore: CGFloat = tree.x(before)
        let yBefore: CGFloat = tree.y(before)

        InlineStyle.set(fixture.header, property: "height", value: "80px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: LayoutID = try #require(fixture.absolute.ref.layoutID)
        #expect(fixture.tree.x(after) == xBefore)
        #expect(fixture.tree.y(after) == yBefore)
    }

    @Test func growingNestedListItemMovesFollowingItem() throws {
        let fixture: NestedListFixture = makeNestedListFixture()
        var tree: LayoutTree = fixture.tree
        let before: LayoutID = try #require(fixture.secondItem.ref.layoutID)
        let yBefore: CGFloat = tree.y(before)

        InlineStyle.set(fixture.firstItem, property: "height", value: "80px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let after: LayoutID = try #require(fixture.secondItem.ref.layoutID)
        #expect(fixture.tree.y(after) == yBefore + 60)
    }

    @Test func rtlLineStaysRightAlignedAfterPreviousSiblingGrows() throws {
        let fixture: RTLFixture = makeRTLFixture()
        var tree: LayoutTree = fixture.tree
        let blockBefore: LayoutID = try #require(fixture.rtl.ref.layoutID)
        let yBefore: CGFloat = tree.y(blockBefore)
        let textBefore: LayoutID = try #require(
            treeToList(tree, blockBefore).first(where: { tree.isText($0) })
        )
        #expect(
            tree.x(textBefore) + tree.textData(textBefore).metrics.width
                == tree.x(blockBefore) + tree.width(blockBefore)
        )

        InlineStyle.set(fixture.header, property: "height", value: "80px")
        fixture.frame.setNeedsRender()
        fixture.frame.setNeedsLayout()
        fixture.frame.render()

        let treeAfter: LayoutTree = fixture.tree
        let blockAfter: LayoutID = try #require(fixture.rtl.ref.layoutID)
        let textAfter: LayoutID = try #require(
            treeToList(treeAfter, blockAfter).first(where: { treeAfter.isText($0) })
        )
        #expect(treeAfter.y(blockAfter) == yBefore + 70)
        #expect(
            treeAfter.x(textAfter) + treeAfter.textData(textAfter).metrics.width
                == treeAfter.x(blockAfter) + treeAfter.width(blockAfter)
        )
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

    var tree: LayoutTree {
        guard var tree: LayoutTree = frame.document else {
            preconditionFailure("fixture has no layout tree")
        }
        return tree
    }
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

    var tree: LayoutTree {
        guard var tree: LayoutTree = frame.document else {
            preconditionFailure("fixture has no layout tree")
        }
        return tree
    }
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

    var tree: LayoutTree {
        guard var tree: LayoutTree = frame.document else {
            preconditionFailure("fixture has no layout tree")
        }
        return tree
    }
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

    var tree: LayoutTree {
        guard var tree: LayoutTree = frame.document else {
            preconditionFailure("fixture has no layout tree")
        }
        return tree
    }
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
