import CoreGraphics

@MainActor
class AccessibilityNode {
    let node: DOMRef
    weak var parent: AccessibilityNode?
    var children: [AccessibilityNode] = []
    var role: String = "none"
    var live: String = "off"
    var text: String = ""
    var bounds: Rect

    init(node: DOMRef, parent: AccessibilityNode? = nil) {
        self.node = node
        self.parent = parent
        self.bounds = AccessibilityNode.computeBounds(for: node)
        self.role = AccessibilityNode.computeRole(for: node)
        self.live = AccessibilityNode.computeLive(for: node)
        self.text = AccessibilityNode.computeText(for: node)
    }

    private static func computeBounds(for node: DOMRef) -> Rect {
        guard let tree: LayoutTree = node.dom.layoutBox?.tree,
            let id: LayoutID = node.layoutID
        else {
            return Rect(left: 0, top: 0, right: 0, bottom: 0)
        }

        if tree.isText(id),
            let line: LayoutID = tree.parentID(of: id),
            let block: LayoutID = tree.parentID(of: line),
            tree.isBlock(block)
        {
            var result: Rect? = nil
            for lineLayout in tree.childrenIDs(of: block) {
                for item in tree.childrenIDs(of: lineLayout)
                where tree.domID(of: item) == node.id {
                    let x: CGFloat = tree.x(item)
                    let y: CGFloat = tree.y(item)
                    let r: Rect = Rect(
                        left: x, top: y,
                        right: x + tree.textTextWidth(item), bottom: y + tree.height(item)
                    )
                    result = result.map { union($0, r) } ?? r
                }
            }
            if let r = result { return r }
        }
        return tree.absoluteBounds(id)
    }

    private static func union(_ a: Rect, _ b: Rect) -> Rect {
        Rect(
            left: min(a.left, b.left),
            top: min(a.top, b.top),
            right: max(a.right, b.right),
            bottom: max(a.bottom, b.bottom)
        )
    }

    private static func computeRole(for node: DOMRef) -> String {
        if node.text != nil { return "StaticText" }
        guard let el = node.element else { return "none" }
        switch el.tag {
        case "input":
            let type: String = el.attributes["type"] ?? ""
            if type == "checkbox" {
                return el.attributes["checked"] != nil ? "checked" : "unchecked"
            }
            return "textbox"
        case "a": return "link"
        case "button": return "button"
        case "html": return "document"
        case "iframe": return "iframe"
        case "canvas", "img":
            return "image"

        default:
            if el.attributes["tabindex"] != nil { return "focusable" }
            if el.attributes["role"] == "alert" { return "alert" }
            return "none"
        }
    }

    private static func computeLive(for node: DOMRef) -> String {
        guard let el = node.element else { return "off" }
        let live: String = el.attributes["aria-live"] ?? "off"
        if live == "assertive" || live == "polite" { return live }
        return "off"
    }

    private static func computeText(for node: DOMRef) -> String {
        if let text = node.text {
            return text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let el = node.element else { return "" }
        if let label = el.attributes["aria-label"], !label.isEmpty { return label }
        if let alt = el.attributes["alt"], !alt.isEmpty { return alt }
        switch el.tag {
            case "canvas":
                let fallback: String = AccessibilityNode.descendantText(node)
                return fallback.isEmpty ? "Canvas" : fallback
            case "input":
                if el.attributes["type"] == "checkbox" {
                    return el.attributes["label"] ?? ""
                }
                return el.attributes["value"] ?? ""
            default: return ""
        }
    }

    private static func descendantText(_ node: DOMRef) -> String {
        var parts: [String] = []
        for child in node.children {
            if let text = child.text {
                let trimmed: String = text.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { parts.append(trimmed) }
            } else {
                let nested: String = AccessibilityNode.descendantText(child)
                if !nested.isEmpty { parts.append(nested) }
            }
        }
        return parts.joined(separator: " ")
    }

    func build() {
        for childNode in node.children {
            buildInternal(childNode)
        }

        if node.layoutID == nil, let first = children.first {
            bounds = children.dropFirst().reduce(first.bounds) {
                AccessibilityNode.union($0, $1.bounds)
            }
        }
    }

    func buildInternal(_ childNode: DOMRef) {
        if let text = childNode.text, text.text.allSatisfy({ $0.isWhitespace }) {
            return
        }
        if let el = childNode.element, el.tag == "style" || el.tag == "script" {
            return
        }
        let child: AccessibilityNode
        if let el = childNode.element, el.tag == "iframe",
            let frame = el.frame, frame.loaded, childNode.layoutID != nil
        {
            child = FrameAccessibilityNode(node: childNode, parent: self)
        } else {
            child = AccessibilityNode(node: childNode, parent: self)
        }
        if child.role != "none" || child.live != "off" {
            children.append(child)
            child.build()
        } else {
            for grandchild in childNode.children {
                buildInternal(grandchild)
            }
        }
    }

    func hitTest(x: CGFloat, y: CGFloat) -> AccessibilityNode? {
        var result: AccessibilityNode? = nil
        if bounds.containsPoint(x, y) { result = self }
        for child in children {
            if let hit = child.hitTest(x: x, y: y) { result = hit }
        }
        return result
    }

    func mapToParent(_ rect: inout Rect) {}

    func absoluteBounds() -> Rect {
        var rect: Rect = bounds
        var current: AccessibilityNode? = (self is FrameAccessibilityNode) ? parent : self
        while let node = current {
            node.mapToParent(&rect)
            current = node.parent
        }
        return rect
    }
}
