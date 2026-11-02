import CoreGraphics
import Testing

@testable import Engine

@Suite
@MainActor
struct DOMTreeTests {

    // MARK: - Element data
    @Test func elementTagIsLowercased() {
        let dom: DOMTree = DOMTree()
        let el: NodeID = dom.createElement(tag: "div", attributes: [:])
        #expect(dom.tag(of: el) == "div")
    }

    @Test func elementStoreAttributes() {
        let dom: DOMTree = DOMTree()
        let el: NodeID = dom.createElement(tag: "a", attributes: ["href": "/home", "class": "nav"])
        #expect(dom.attributes(of: el)?["href"] == "/home")
        #expect(dom.attributes(of: el)?["class"] == "nav")
    }

    @Test func elementDefaultsAreEmpty() {
        let dom: DOMTree = DOMTree()
        let el: NodeID = dom.createElement(tag: "p", attributes: [:])
        #expect(dom.children(of: el).isEmpty)
        #expect(dom.parent(of: el) == nil)
        #expect(dom.style(of: el).computed == .initial)
        #expect(!dom.flags(of: el).isFocused)
    }

    // MARK: - Element description
    @Test func elementDescription() {
        let dom: DOMTree = DOMTree()
        let el: NodeID = dom.createElement(tag: "span", attributes: [:])
        #expect(dom.ref(el).description == "<span>")
    }

    // MARK: - Text data
    @Test func textNodeStoresText() {
        let dom: DOMTree = DOMTree()
        let node: NodeID = dom.createText("Hello")
        #expect(dom.text( node)?.text == "Hello")
    }

    @Test func textNodeDefaultsAreEmpty() {
        let dom: DOMTree = DOMTree()
        let node: NodeID = dom.createText("Hi")
        #expect(dom.children(of: node).isEmpty)
        #expect(dom.parent(of: node) == nil)
        #expect(dom.style(of: node).computed == .initial)
        #expect(!dom.flags(of: node).isFocused)
    }

    // MARK: Text description
    @Test func textNodeDescription() {
        let dom: DOMTree = DOMTree()
        let node: NodeID = dom.createText("world")
        #expect(dom.ref(node).description == "\"world\"")
    }

    // MARK: Parent-child relationships
    @Test func parentChildLink() {
        let dom: DOMTree = DOMTree()
        let parent: NodeID = dom.createElement(tag: "div", attributes: [:])
        let child: NodeID = dom.createText("hi")
        dom.append(child, to: parent)

        #expect(dom.children(of: parent).count == 1)
        #expect(dom.parent(of: child) == parent)
    }

    @Test func nestedElements() {
        let dom: DOMTree = DOMTree()
        let root: NodeID = dom.root
        let body: NodeID = dom.createElement(tag: "body", attributes: [:])
        let text: NodeID = dom.createText("content")
        dom.append(body, to: root)
        dom.append(text, to: body)

        #expect(dom.children(of: root).count == 1)
        #expect(dom.children(of: body).count == 1)
        #expect(dom.parent(of: body) == root)
        #expect(dom.parent(of: text) == body)
    }

    // MARK: - Style and isFocused Mutation

    @Test func styleCanBeSet() {
        let dom: DOMTree = DOMTree()
        let el: NodeID = dom.createElement(tag: "p", attributes: [:])
        let ref: DOMRef = dom.ref(el)
        ref.style.mutate { $0.text.color = BrowserColor(cssName: "red") }
        #expect(ref.style.computed.text.color == BrowserColor(cssName: "red"))
    }

    @Test func isFocusedCanBeToggled() {
        let dom: DOMTree = DOMTree()
        let el: NodeID = dom.createElement(tag: "input", attributes: [:])
        dom.setFlag(\.isFocused, true, of: el)
        #expect(dom.flags(of: el).isFocused)
    }
}
