import XCTest

@testable import Core

final class HTMLParserTests: XCTestCase {

    // MARK: - Helper for cast to Element
    private func el(_ node: any DOMNode) -> Element {
        node as! Element
    }

    // MARK: - Implicit structure - always produces html > body
    func testImplicitHTMLStructure() {
        let root = el(HTMLParser(body: "").parse())
        XCTAssertEqual(root.tag, "html")
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(el(root.children[0]).tag, "body")
    }

    // MARK: - Implicit structure produces html > head + body
    func testImplicitHeadAndBody() {
        let root = el(HTMLParser(body: "<title>T</title><p>hi</p>").parse())
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(el(root.children[0]).tag, "head")
        XCTAssertEqual(el(root.children[1]).tag, "body")
    }

    // MARK: Text content goes into body
    func testTextInBody() {
        let root = el(HTMLParser(body: "hello").parse())
        let body = el(root.children[0])
        XCTAssertEqual(body.children.count, 1)
        let text = body.children[0] as! TextNode
        XCTAssertEqual(text.text, "hello")
    }

    // MARK: - Nested tags
    func testNestedParagraph() {
        let root = el(HTMLParser(body: "<p>world</p>").parse())
        let body = el(root.children[0])
        let p = el(body.children[0])
        XCTAssertEqual(p.tag, "p")
        let text = p.children[0] as! TextNode
        XCTAssertEqual(text.text, "world")
    }

    // MARK: - Attributes are parsed
    func testAttributeParsing() {
        let root = el(HTMLParser(body: #"<a href="/home">link</a>"#).parse())
        let body = el(root.children[0])
        let a = el(body.children[0])
        XCTAssertEqual(a.tag, "a")
        XCTAssertEqual(a.attributes["href"], "/home")
    }

    // MARK: - Self-closing tags don't swallow siblings
    func testSelfClosingBr() {
        let root = el(HTMLParser(body: "before<br>after").parse())
        let body = el(root.children[0])
        // br is a child of body, not a parent of "after"
        XCTAssertEqual(body.children.count, 3)
        XCTAssertEqual(el(body.children[1]).tag, "br")
    }

    // MARK: - Comments and doctype are skipped
    func testDoctypeIsIgnored() {
        let root = el(HTMLParser(body: "<!DOCTYPE html><p>ok</p>").parse())
        let body = el(root.children[0])
        XCTAssertEqual(el(body.children[0]).tag, "p")
    }

    func testHTMLIsIgnored() {
        let root = el(HTMLParser(body: "<-!--- comment ---><p>text</p>").parse())
        let body = el(root.children[0])
        XCTAssertEqual(el(body.children[0]).tag, "p")
    }

    // MARK: - Whitespace-only text is discarded
    func testWhiteSpaceOnlyTextDiscarded() {
        let root = el(HTMLParser(body: "<p>    </p>").parse())
        let body = el(root.children[0])
        let p = el(body.children[0])
        XCTAssertTrue(p.children.isEmpty)
    }
}
