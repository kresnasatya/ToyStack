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

    // MARK: Text content goes into body
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
        // br is a child of body, not a parent of "after"
        #expect(bodyChildren.count == 3)
        #expect(tag(bodyChildren[1], dom) == "br")
    }

    // MARK: - Comments and doctype are skipped
    @Test func doctypeIsIgnored() {
        let dom: DOMTree = HTMLParser(body: "<!DOCTYPE html><p>ok</p>").parse()
        let body: NodeID = children(dom.root, dom)[0]
        #expect(tag(children(body, dom)[0], dom) == "p")
    }

    @Test func htmlIsIgnored() {
        let dom: DOMTree = HTMLParser(body: "<!-- comment --><p>text</p>").parse()
        let body: NodeID = children(dom.root, dom)[0]
        #expect(tag(children(body, dom)[0], dom) == "p")
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
}
