import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct DisplayNoneLayoutTests {
    private let css: String = """
        body { display: block; }
        div { display: block; }
        p { display: block; }
    """

    private func makePage(_ html: String, withBrowserStyles: Bool = false) -> LayoutTestPage {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: css)
        if withBrowserStyles {
            page.frame.setStyleRules(defaultStyleSheet + CSSParser(css).parse().rules)
            page.frame.setNeedsRender()
            page.frame.render()
        }
        return page
    }

    private func layoutTexts(_ page: LayoutTestPage) -> [String] {
        let tree: LayoutTree = page.tree
        return treeToList(tree, tree.rootID)
            .filter({ tree.isText($0) })
            .map({ tree.textString($0) })
    }

    private func setDisplay(_ value: String, of id: String, in page: LayoutTestPage) throws {
        let element: ElementRef = try #require(page.firstElement(id: id))
        InlineStyle.set(element, property: "display", value: value)
        page.frame.setNeedsStyleSubtree(element.ref)
        page.frame.render()
    }

    // MARK: - No box for display: none

    @Test func hiddenBlockChildGetsNoBox() throws {
        let page: LayoutTestPage = makePage(
            #"<div id="box"><p>one</p><p style="display:none">gone</p><p>two</p></div>"#
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let boxLayout: LayoutID = try #require(page.firstBlockID(in: box))
        #expect(page.tree.childrenIDs(of: boxLayout).count == 2)
        #expect(!layoutTexts(page).contains("gone"))
    }

    @Test func hiddenElementInsideInlineContentIsSkipped() {
        let page: LayoutTestPage = makePage(
            #"<p>a <b>bold <span style="display:none">secret</span></b> b</p>"#
        )
        #expect(layoutTexts(page) == ["a", "bold", "b"])
    }

    @Test func hiddenElementHidesItsWholeSubtree() {
        let page: LayoutTestPage = makePage(
            #"<div style="display:none"><p>deep <b>deeper</b></p></div><p>shown</p>"#
        )
        #expect(layoutTexts(page) == ["shown"])
    }

    // MARK: - Browser stylesheet hides non-rendered elements

    @Test func scriptAndStyleTextStayHiddenNextToFlexContent() {
        let page: LayoutTestPage = makePage(
            #"<style>#bar{color:red}</style><div style="display:flex">Flex</div><script>var x = 1;</script>"#,
            withBrowserStyles: true
        )
        #expect(layoutTexts(page) == ["Flex"])
    }

    @Test func headTitleAndTemplateAreNotDrawn() {
        let page: LayoutTestPage = makePage(
            #"<html><head><title>Tab title</title></head><body><template id="B:0"></template><p>body</p></body></html>"#,
            withBrowserStyles: true
        )
        #expect(layoutTexts(page) == ["body"])
    }

    @Test func hiddenAttributeHidesElement() {
        let page: LayoutTestPage = makePage(
            #"<section hidden id="S:0"><p>streamed</p></section><p>shown</p>"#,
            withBrowserStyles: true
        )
        #expect(layoutTexts(page) == ["shown"])
    }

    @Test func authorStyleCanShowAHiddenElement() {
        let page: LayoutTestPage = LayoutTestPage(html: #"<div hidden>visible</div>"#, rules: "")
        page.frame.setStyleRules(defaultStyleSheet + CSSParser("div { display: block; }").parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()
        #expect(layoutTexts(page) == ["visible"])
    }

    // MARK: - Showing and hiding later relays out

    @Test func showingAHiddenBlockChildAddsItsBox() throws {
        let page: LayoutTestPage = makePage(
            #"<div id="box"><p>one</p><p id="two" style="display:none">two</p></div>"#
        )
        try setDisplay("block", of: "two", in: page)

        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let boxLayout: LayoutID = try #require(page.firstBlockID(in: box))
        #expect(page.tree.childrenIDs(of: boxLayout).count == 2)
        #expect(layoutTexts(page).contains("two"))
        expectIncrementalMatchesFull(page)
    }

    @Test func hidingABlockChildRemovesItsBox() throws {
        let page: LayoutTestPage = makePage(
            #"<div id="box"><p>one</p><p id="two">two</p></div>"#
        )
        try setDisplay("none", of: "two", in: page)

        #expect(!layoutTexts(page).contains("two"))
        expectIncrementalMatchesFull(page)
    }

    @Test func showingANestedInlineElementAddsItsText() throws {
        let page: LayoutTestPage = makePage(
            #"<p>a <b>bold <span id="s" style="display:none">secret</span></b></p>"#
        )
        try setDisplay("inline", of: "s", in: page)

        #expect(layoutTexts(page).contains("secret"))
        expectIncrementalMatchesFull(page)
    }

    @Test func appendingAHiddenElementAddsNoBox() throws {
        let page: LayoutTestPage = makePage(#"<div id="box"><p>one</p><p>two</p></div>"#)
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let boxLayout: LayoutID = try #require(page.firstBlockID(in: box))
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(script: "append", code: """
            var p = document.createElement('p');
            p.setAttribute('style', 'display:none');
            p.textContent = 'gone';
            document.getElementById('box').appendChild(p);
        """)
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(page.tree.childrenIDs(of: boxLayout).count == 2)
        #expect(!layoutTexts(page).contains("gone"))
        expectIncrementalMatchesFull(page)
    }
}
