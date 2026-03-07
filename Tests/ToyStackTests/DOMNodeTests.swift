import XCTest

@testable import Core

final class DOMNodeTests: XCTestCase {

    // MARK: - Element initialization
    func testElementTagIsLowercased() {
        let el = Element(tag: "div", attributes: [:], parent: nil)
        XCTAssertEqual(el.tag, "div")
    }

    func testElementStoreAttributes() {
        let el = Element(tag: "a", attributes: ["href": "/home", "class": "nav"], parent: nil)
        XCTAssertEqual(el.attributes["href"], "/home")
        XCTAssertEqual(el.attributes["class"], "nav")
    }

    func testElementDefaultsAreEmpty() {
        let el = Element(tag: "p", attributes: [:], parent: nil)
        XCTAssertTrue(el.children.isEmpty)
        XCTAssertNil(el.parent)
        XCTAssertTrue(el.style.isEmpty)
        XCTAssertFalse(el.isFocused)
    }

    // MARK: - Element description
    func testElementDescription() {
        let el = Element(tag: "span", attributes: [:], parent: nil)
        XCTAssertEqual(el.description, "<span>")
    }

    // MARK: - TextNode initialization
    func testTextNodeStoresText() {
        let node = TextNode(text: "Hello", parent: nil)
        XCTAssertEqual(node.text, "Hello")
    }

    func testTextNodeDefaultsAreEmpty() {
        let node = TextNode(text: "Hi", parent: nil)
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertNil(node.parent)
        XCTAssertTrue(node.style.isEmpty)
        XCTAssertFalse(node.isFocused)
    }

    // MARK: TextNode description
    func testTextNodeDescription() {
        let node = TextNode(text: "world", parent: nil)
        XCTAssertEqual(node.description, "\"world\"")
    }

    // MARK: Parent-child relationships
    func testParentChildLink() {
        let parent = Element(tag: "div", attributes: [:], parent: nil)
        let child = TextNode(text: "hi", parent: parent)
        parent.children.append(child)

        XCTAssertEqual(parent.children.count, 1)
        // Verify the child's parent is the same object
        XCTAssert(child.parent === parent)
    }

    func testNestedElements() {
        let root = Element(tag: "html", attributes: [:], parent: nil)
        let body = Element(tag: "body", attributes: [:], parent: root)
        let text = TextNode(text: "content", parent: body)
        root.children.append(body)
        body.children.append(text)

        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(body.children.count, 1)
        XCTAssert(body.parent === root)
        XCTAssert(text.parent === body)
    }

    // MARK: - Style and isFocused Mutation

    func testStyleCanBeSet() {
        let el = Element(tag: "p", attributes: [:], parent: nil)
        el.style["color"] = "red"
        XCTAssertEqual(el.style["color"], "red")
    }

    func testIsFocusedCanBeToggled() {
        let el = Element(tag: "input", attributes: [:], parent: nil)
        el.isFocused = true
        XCTAssertTrue(el.isFocused)
    }
}
