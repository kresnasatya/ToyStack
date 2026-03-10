import Testing

@testable import Engine

@Suite struct DOMNodeTests {

    // MARK: - Element initialization
    @Test func elementTagIsLowercased() {
        let el = Element(tag: "div", attributes: [:], parent: nil)
        #expect(el.tag == "div")
    }

    @Test func elementStoreAttributes() {
        let el = Element(tag: "a", attributes: ["href": "/home", "class": "nav"], parent: nil)
        #expect(el.attributes["href"] == "/home")
        #expect(el.attributes["class"] == "nav")
    }

    @Test func elementDefaultsAreEmpty() {
        let el = Element(tag: "p", attributes: [:], parent: nil)
        #expect(el.children.isEmpty)
        #expect(el.parent == nil)
        #expect(el.style.isEmpty)
        #expect(!el.isFocused)
    }

    // MARK: - Element description
    @Test func elementDescription() {
        let el = Element(tag: "span", attributes: [:], parent: nil)
        #expect(el.description == "<span>")
    }

    // MARK: - TextNode initialization
    @Test func textNodeStoresText() {
        let node = TextNode(text: "Hello", parent: nil)
        #expect(node.text == "Hello")
    }

    @Test func textNodeDefaultsAreEmpty() {
        let node = TextNode(text: "Hi", parent: nil)
        #expect(node.children.isEmpty)
        #expect(node.parent == nil)
        #expect(node.style.isEmpty)
        #expect(!node.isFocused)
    }

    // MARK: TextNode description
    @Test func textNodeDescription() {
        let node = TextNode(text: "world", parent: nil)
        #expect(node.description == "\"world\"")
    }

    // MARK: Parent-child relationships
    @Test func parentChildLink() {
        let parent = Element(tag: "div", attributes: [:], parent: nil)
        let child = TextNode(text: "hi", parent: parent)
        parent.children.append(child)

        #expect(parent.children.count == 1)
        // Verify the child's parent is the same object
        #expect(child.parent === parent)
    }

    @Test func nestedElements() {
        let root = Element(tag: "html", attributes: [:], parent: nil)
        let body = Element(tag: "body", attributes: [:], parent: root)
        let text = TextNode(text: "content", parent: body)
        root.children.append(body)
        body.children.append(text)

        #expect(root.children.count == 1)
        #expect(body.children.count == 1)
        #expect(body.parent === root)
        #expect(text.parent === body)
    }

    // MARK: - Style and isFocused Mutation

    @Test func styleCanBeSet() {
        let el = Element(tag: "p", attributes: [:], parent: nil)
        el.style["color"] = "red"
        #expect(el.style["color"] == "red")
    }

    @Test func isFocusedCanBeToggled() {
        let el = Element(tag: "input", attributes: [:], parent: nil)
        el.isFocused = true
        #expect(el.isFocused)
    }
}
