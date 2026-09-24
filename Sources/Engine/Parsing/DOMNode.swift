import Foundation

// MARK: - DOMNode
protocol DOMNode: AnyObject {
    var children: [any DOMNode] { get set }
    var parent: (any DOMNode)? { get set }
    var style: [String: String] { get set }
    var isFocused: Bool { get set }
    var isFocusVisible: Bool { get set }
    var satisfiedHas: Set<Int> { get set }
    var layoutObject: LayoutObject? { get set }
    var animations: [String: Animation] { get set }
}

// MARK: - Element
class Element: DOMNode {
    let tag: String
    var attributes: [String: String]
    var children: [any DOMNode] = []
    var parent: (any DOMNode)?
    var style: [String: String] = [:]
    var isFocused: Bool = false
    var isFocusVisible: Bool = false
    var isChecked: Bool = false
    var satisfiedHas: Set<Int> = []
    var layoutObject: LayoutObject? = nil
    var animations: [String: Animation] = [:]
    var scrollOffsetY: CGFloat = 0

    init(tag: String, attributes: [String: String], parent: (any DOMNode)?) {
        self.tag = tag
        self.attributes = attributes
        self.parent = parent
    }
}

extension Element: CustomStringConvertible {
    var description: String { "<\(tag)>" }
}

// MARK: - TextNode
class TextNode: DOMNode {
    let text: String
    var children: [any DOMNode] = []
    var parent: (any DOMNode)?
    var style: [String: String] = [:]
    var isFocused: Bool = false
    var isFocusVisible: Bool = false
    var satisfiedHas: Set<Int> = []
    var layoutObject: LayoutObject? = nil
    var animations: [String: Animation] = [:]

    init(text: String, parent: (any DOMNode)?) {
        self.text = text
        self.parent = parent
    }
}

extension TextNode: CustomStringConvertible {
    var description: String { "\"\(text)\"" }
}
