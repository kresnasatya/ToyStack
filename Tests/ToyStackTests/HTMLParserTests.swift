import Testing

@testable import Engine

@Suite struct HTMLParserTests {

    // MARK: - Helper for cast to Element
    private func el(_ node: any DOMNode) -> Element {
        node as! Element
    }

    // MARK: - Implicit structure - always produces html > body
    @Test func implicitHTMLStructure() {
        let root = el(HTMLParser(body: "").parse())
        #expect(root.tag == "html")
        #expect(root.children.count == 1)
        #expect(el(root.children[0]).tag == "body")
    }

    // MARK: - Implicit structure produces html > head + body
    @Test func implicitHeadAndBody() {
        let root = el(HTMLParser(body: "<title>T</title><p>hi</p>").parse())
        #expect(root.children.count == 2)
        #expect(el(root.children[0]).tag == "head")
        #expect(el(root.children[1]).tag == "body")
    }

    // MARK: Text content goes into body
    @Test func textInBody() {
        let root = el(HTMLParser(body: "hello").parse())
        let body = el(root.children[0])
        #expect(body.children.count == 1)
        let text = body.children[0] as! TextNode
        #expect(text.text == "hello")
    }

    // MARK: - Nested tags
    @Test func nestedParagraph() {
        let root = el(HTMLParser(body: "<p>world</p>").parse())
        let body = el(root.children[0])
        let p = el(body.children[0])
        #expect(p.tag == "p")
        let text = p.children[0] as! TextNode
        #expect(text.text == "world")
    }

    // MARK: - Attributes are parsed
    @Test func attributeParsing() {
        let root = el(HTMLParser(body: #"<a href="/home">link</a>"#).parse())
        let body = el(root.children[0])
        let a = el(body.children[0])
        #expect(a.tag == "a")
        #expect(a.attributes["href"] == "/home")
    }

    // MARK: - Self-closing tags don't swallow siblings
    @Test func selfClosingBr() {
        let root = el(HTMLParser(body: "before<br>after").parse())
        let body = el(root.children[0])
        // br is a child of body, not a parent of "after"
        #expect(body.children.count == 3)
        #expect(el(body.children[1]).tag == "br")
    }

    // MARK: - Comments and doctype are skipped
    @Test func doctypeIsIgnored() {
        let root = el(HTMLParser(body: "<!DOCTYPE html><p>ok</p>").parse())
        let body = el(root.children[0])
        #expect(el(body.children[0]).tag == "p")
    }

    @Test func htmlIsIgnored() {
        let root = el(HTMLParser(body: "<!-- comment --><p>text</p>").parse())
        let body = el(root.children[0])
        #expect(el(body.children[0]).tag == "p")
    }

    // MARK: - Whitespace-only text is discarded
    @Test func whiteSpaceOnlyTextDiscarded() {
        let root = el(HTMLParser(body: "<p>    </p>").parse())
        let body = el(root.children[0])
        let p = el(body.children[0])
        #expect(p.children.isEmpty)
    }
}
