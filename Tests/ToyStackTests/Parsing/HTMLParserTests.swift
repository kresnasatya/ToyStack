import Testing

@testable import Engine

@Suite
@MainActor
struct HTMLParserTests {

    private func tag(_ id: NodeID, _ dom: DOMTree) -> String? {
        dom.tag(of: id)
    }

    private func children(_ id: NodeID, _ dom: DOMTree) -> [NodeID] {
        dom.children(of: id)
    }

    // MARK: - Implicit structure - always produces html > body
    @Test func implicitHTMLStructure() {
        let dom: DOMTree = HTMLParser(body: "").parse()
        #expect(tag(dom.root, dom) == "html")
        #expect(children(dom.root, dom).count == 1)
        #expect(tag(children(dom.root, dom)[0], dom) == "body")
    }

    // MARK: - Implicit structure produces html > head + body
    @Test func implicitHeadAndBody() {
        let dom: DOMTree = HTMLParser(body: "<title>T</title><p>hi</p>").parse()
        let rootChildren: [NodeID] = children(dom.root, dom)
        #expect(rootChildren.count == 2)
        #expect(tag(rootChildren[0], dom) == "head")
        #expect(tag(rootChildren[1], dom) == "body")
    }

    // MARK: - Text content goes into body
    @Test func textInBody() {
        let dom: DOMTree = HTMLParser(body: "hello").parse()
        let body: NodeID = children(dom.root, dom)[0]
        let bodyChildren: [NodeID] = children(body, dom)
        #expect(bodyChildren.count == 1)
        #expect(dom.text( bodyChildren[0])?.text == "hello")
    }

    // MARK: - Nested tags
    @Test func nestedParagraph() {
        let dom: DOMTree = HTMLParser(body: "<p>world</p>").parse()
        let body: NodeID = children(dom.root, dom)[0]
        let p: NodeID = children(body, dom)[0]
        #expect(tag(p, dom) == "p")
        #expect(dom.text( children(p, dom)[0])?.text == "world")
    }

    // MARK: - Attributes are parsed
    @Test func attributeParsing() {
        let dom: DOMTree = HTMLParser(body: #"<a href="/home">link</a>"#).parse()
        let body: NodeID = children(dom.root, dom)[0]
        let a: NodeID = children(body, dom)[0]
        #expect(tag(a, dom) == "a")
        #expect(dom.attributes(of: a)?["href"] == "/home")
    }

    // MARK: - Self-closing tags don't swallow siblings
    @Test func selfClosingBr() {
        let dom: DOMTree = HTMLParser(body: "before<br>after").parse()
        let body: NodeID = children(dom.root, dom)[0]
        let bodyChildren: [NodeID] = children(body, dom)
        #expect(bodyChildren.count == 3)
        #expect(tag(bodyChildren[1], dom) == "br")
    }

    // MARK: - Doctype and comments before any tag are skipped
    @Test func doctypeIsIgnored() {
        let dom: DOMTree = HTMLParser(body: "<!DOCTYPE html><p>ok</p>").parse()
        let body: NodeID = children(dom.root, dom)[0]
        #expect(tag(children(body, dom)[0], dom) == "p")
    }

    @Test func commentBeforeAnyTagIsDropped() {
        let dom: DOMTree = HTMLParser(body: "<!-- comment --><p>text</p>").parse()
        #expect(children(dom.root, dom).count == 1)
        let body: NodeID = children(dom.root, dom)[0]
        #expect(tag(children(body, dom)[0], dom) == "p")
    }

    // MARK: - Comments inside the document become nodes
    @Test func commentBetweenTextsIsANode() {
        let dom: DOMTree = HTMLParser(body: "<p>a<!--$?-->b</p>").parse()
        let body: NodeID = children(dom.root, dom)[0]
        let p: NodeID = children(body, dom)[0]
        let descriptions: [String] = children(p, dom).map({ dom.ref($0).description })
        #expect(descriptions == ["\"a\"", "<!--$?-->", "\"b\""])
    }

    @Test func commentKeepsTagLikeText() throws {
        let dom: DOMTree = HTMLParser(body: "<p><!-- <b>x</b> --></p>").parse()
        let body: NodeID = children(dom.root, dom)[0]
        let p: NodeID = children(body, dom)[0]
        let pChildren: [NodeID] = children(p, dom)
        #expect(pChildren.count == 1)
        let comment: NodeID = try #require(pChildren.first)
        #expect(dom.comment(comment)?.data == " <b>x</b> ")
    }

    @Test func unclosedCommentRunsToEndOfInput() {
        let dom: DOMTree = HTMLParser(body: "<p>a<!-- never closed").parse()
        let body: NodeID = children(dom.root, dom)[0]
        let p: NodeID = children(body, dom)[0]
        let descriptions: [String] = children(p, dom).map({ dom.ref($0).description })
        #expect(descriptions == ["\"a\"", "<!-- never closed-->"])
    }

    // MARK: - Syntax highlighter reads tokens without building a document
    @Test func highlighterDoesNotBuildImplicitTags() {
        let html: String = HTMLSyntaxHighlighter(body: "<p>x</p>").highlight()
        #expect(html == "<pre>&lt;p&gt;<b>x</b>&lt;/p&gt;</pre>")
    }

    // MARK: - Whitespace-only text is preserved for layout to collapse
    @Test func whiteSpaceOnlyTextPreserved() {
        let dom: DOMTree = HTMLParser(body: "<p>    </p>").parse()
        let body: NodeID = children(dom.root, dom)[0]
        let p: NodeID = children(body, dom)[0]
        let pChildren: [NodeID] = children(p, dom)
        #expect(pChildren.count == 1)
        #expect(dom.text( pChildren[0])?.text == "    ")
    }

    // MARK: - Self-closing tags in SVG and MathML

    private func describe(_ id: NodeID, _ dom: DOMTree) -> [String] {
        children(id, dom).map({ dom.ref($0).description })
    }

    private func firstElement(_ tagName: String, _ dom: DOMTree) -> NodeID? {
        treeToList(dom.ref(dom.root)).first(where: { dom.tag(of: $0.id) == tagName })?.id
    }

    // HTML §13.2.6.5: inside <svg> a start tag ending in "/>" closes itself. Without
    // that, every icon swallows the rest of the page into its last <path>.
    @Test func svgSelfClosingChildrenStayInsideTheSVG() throws {
        let dom: DOMTree = HTMLParser(
            body: #"<div id="box"><svg viewBox="0 0 4 4"><path d="M0 0"/><path d="M1 1" /></svg><p>after</p></div>"#
        ).parse()
        let box: NodeID = try #require(firstElement("div", dom))
        let svg: NodeID = try #require(firstElement("svg", dom))
        #expect(describe(box, dom) == ["<svg>", "<p>"])
        #expect(describe(svg, dom) == ["<path>", "<path>"])
    }

    // HTML §13.2.6.4.7: an <svg/> or <math/> start tag in the body is popped right away.
    @Test func selfClosingSVGElementItselfCloses() throws {
        let dom: DOMTree = HTMLParser(body: #"<div><svg/><p>after</p></div>"#).parse()
        let div: NodeID = try #require(firstElement("div", dom))
        #expect(describe(div, dom) == ["<svg>", "<p>"])
    }

    @Test func mathMLSelfClosingChildrenStayInsideTheMath() throws {
        let dom: DOMTree = HTMLParser(body: #"<math><mspace/><mi>x</mi></math><p>after</p>"#).parse()
        let math: NodeID = try #require(firstElement("math", dom))
        #expect(describe(math, dom) == ["<mspace>", "<mi>"])
    }

    // HTML §13.2.2 (non-void-html-element-start-tag-with-trailing-solidus): on an
    // ordinary HTML element the "/" is ignored, so <div/> stays open.
    @Test func slashOnAnHTMLElementDoesNotCloseIt() throws {
        let dom: DOMTree = HTMLParser(body: #"<div/><p>inside</p>"#).parse()
        let div: NodeID = try #require(firstElement("div", dom))
        #expect(describe(div, dom) == ["<p>"])
    }
}
