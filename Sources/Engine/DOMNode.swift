import Foundation

// MARK: - DOMNode
// A class-bound protocol that unifies Element and TextNode.
// "AnyObject" means only reference types (classes) can adopt it -
// required so we can store weak/unowned references and compare by identity
protocol DOMNode: AnyObject {
    var children: [any DOMNode] { get set }
    var parent: (any DOMNode)? { get set }
    var style: [String: String] { get set }
    var isFocused: Bool { get set }
    var satisfiedHas: Set<Int> { get set }
}

// MARK: - Element
// Represents an HTML tag node, e.g. <div class="box">.
class Element: DOMNode {
    let tag: String  // tag name, always lowercased
    var attributes: [String: String]
    var children: [any DOMNode] = []
    var parent: (any DOMNode)?
    var style: [String: String] = [:]
    var isFocused: Bool = false
    var satisfiedHas: Set<Int> = []

    init(tag: String, attributes: [String: String], parent: (any DOMNode)?) {
        self.tag = tag
        self.attributes = attributes
        self.parent = parent
    }
}

// CustomStringConvertible lets you print an Element as "<div>" for debugging.
extension Element: CustomStringConvertible {
    var description: String { "<\(tag)>" }
}

// MARK: - TextNode
// Represents a text node, e.g. the "Hello" inside <p>Hello</p>.
// Named TextNode (not Text) to avoid collision with SwiftUI's Text view.
class TextNode: DOMNode {
    let text: String  // the raw text content
    var children: [any DOMNode] = []
    var parent: (any DOMNode)?
    var style: [String: String] = [:]
    var isFocused: Bool = false
    var satisfiedHas: Set<Int> = []

    init(text: String, parent: (any DOMNode)?) {
        self.text = text
        self.parent = parent
    }
}

extension TextNode: CustomStringConvertible {
    // Wraps text in quotes to mimic Python's repr(self.text).
    var description: String { "\"\(text)\"" }
}
