import CoreGraphics
import Foundation

// MARK: - DOMNode
protocol DOMNode: AnyObject {
    var children: [any DOMNode] { get set }
    var parent: (any DOMNode)? { get set }
    var style: StyleFields { get }
    var isFocused: Bool { get set }
    var isFocusVisible: Bool { get set }
    var isHovered: Bool { get set }
    var satisfiedHas: Set<Int> { get set }
    var layoutObject: LayoutObject? { get set }
    var animations: [String: Animation] { get set }
}

extension DOMNode {
    var inheritedStyleOwner: any DOMNode {
        if self is TextNode, let parent { return parent }
        return self
    }

    func isInclusiveAncestor(of node: any DOMNode) -> Bool {
        var current: (any DOMNode)? = node
        while let candidate = current {
            if candidate === self { return true }
            current = candidate.parent
        }
        return false
    }
}

// MARK: - Element
class Element: DOMNode {
    let tag: String
    var attributes: [String: String]
    var children: [any DOMNode] = []
    var parent: (any DOMNode)?
    var style: StyleFields = StyleFields()
    var isFocused: Bool = false
    var isFocusVisible: Bool = false
    var isHovered: Bool = false
    var isChecked: Bool = false
    var satisfiedHas: Set<Int> = []
    weak var layoutObject: LayoutObject? = nil
    var animations: [String: Animation] = [:]
    var scrollOffsetY: CGFloat = 0
    var image: CGImage? = nil
    var backgroundImage: CGImage? = nil
    var backgroundImageSource: String? = nil
    var frame: Frame? = nil
    var frameSource: String? = nil
    var canvasContext: CanvasRenderingContext2D? = nil

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
    private(set) var text: String
    var children: [any DOMNode] = []
    var parent: (any DOMNode)?
    var style: StyleFields = StyleFields()
    var isFocused: Bool = false
    var isHovered: Bool = false
    var isFocusVisible: Bool = false
    var satisfiedHas: Set<Int> = []
    weak var layoutObject: LayoutObject? = nil
    var animations: [String: Animation] = [:]

    init(text: String, parent: (any DOMNode)?) {
        self.text = text
        self.parent = parent
    }

    @MainActor
    func append(_ suffix: String) {
        text += suffix
        LayoutInvalidation.textChanged(self)
    }
}

extension TextNode: CustomStringConvertible {
    var description: String { "\"\(text)\"" }
}
