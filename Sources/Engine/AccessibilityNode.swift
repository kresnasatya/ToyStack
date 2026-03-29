import CoreGraphics

class AccessibilityNode {
    let node: DOMNode
    weak var parent: AccessibilityNode?
    var children: [AccessibilityNode] = []
    var role: String = "none"
    var text: String = ""
    var bounds: Rect

    init(node: DOMNode, parent: AccessibilityNode? = nil) {
        self.node = node
        self.parent = parent
        self.bounds = AccessibilityNode.computeBounds(for: node)
        self.role = AccessibilityNode.computeRole(for: node)
    }

    private static func computeBounds(for node: DOMNode) -> Rect {
        if let lo = node.layoutObject {
            return Rect(left: lo.x, top: lo.y, right: lo.x + lo.width, bottom: lo.y + lo.height)
        }
        return Rect(left: 0, top: 0, right: 0, bottom: 0)
    }

    private static func computeRole(for node: DOMNode) -> String {
        if node is TextNode { return "StaticText" }
        guard let el = node as? Element else { return "none" }
        switch el.tag {
        case "input":
            let type = el.attributes["type"] ?? ""
            if type == "checkbox" {
                return el.attributes["checked"] != nil ? "checked" : "unchecked"
            }
            return "textbox"
        case "a": return "link"
        case "button": return "button"
        case "html": return "document"
        default:
            if el.attributes["tabindex"] != nil { return "focusable" }
            if el.tag == "div" && el.attributes["role"] == "alert" { return "alert" }
            return "none"
        }
    }

    func build() {
        var built: [AccessibilityNode] = []
        for childNode in node.children {
            let child = AccessibilityNode(node: childNode, parent: self)
            if child.role != "none" {
                child.build()
                built.append(child)
            }
        }
        children = built
        text = computeText()
    }

    private func computeText() -> String {
        if let t = node as? TextNode { return t.text }
        if let el = node as? Element {
            if role == "textbox" { return el.attributes["value"] ?? "" }
            if role == "checked" || role == "unchecked" {
                return el.attributes["label"] ?? ""
            }
        }
        return children.compactMap({ $0.text.isEmpty ? nil : $0.text }).joined(separator: " ")
    }

    func hitTest(x: CGFloat, y: CGFloat) -> AccessibilityNode? {
        var result: AccessibilityNode? = nil
        if bounds.containsPoint(x, y) { result = self }
        for child in children {
            if let hit = child.hitTest(x: x, y: y) { result = hit }
        }
        return result
    }
}
