import CoreGraphics

class AccessibilityNode {
    let node: DOMNode
    weak var parent: AccessibilityNode?
    var children: [AccessibilityNode] = []
    var role: String = "none"
    var live: String = "off"
    var text: String = ""
    var bounds: Rect

    init(node: DOMNode, parent: AccessibilityNode? = nil) {
        self.node = node
        self.parent = parent
        self.bounds = AccessibilityNode.computeBounds(for: node)
        self.role = AccessibilityNode.computeRole(for: node)
        self.live = AccessibilityNode.computeLive(for: node)
    }

    private static func computeBounds(for node: DOMNode) -> Rect {
        guard let lo = node.layoutObject else {
            return Rect(left: 0, top: 0, right: 0, bottom: 0)
        }
        // Text is laid out one word at a time, and layoutObject only
        // remembers the last word. Union every word rect for this node.
        if lo is TextLayout, let line = lo.parent, let block = line.parent {
            var result: Rect? = nil
            for lineLayout in block.children {
                for item in lineLayout.children where item.node === node {
                    let r = Rect(
                        left: item.x, top: item.y,
                        right: item.x + item.width, bottom: item.y + item.height
                    )
                    result = result.map { union($0, r) } ?? r
                }
            }
            if let r = result { return r }
        }
        return Rect(left: lo.x, top: lo.y, right: lo.x + lo.width, bottom: lo.y + lo.height)
    }

    private static func union(_ a: Rect, _ b: Rect) -> Rect {
        Rect(
            left: min(a.left, b.left),
            top: min(a.top, b.top),
            right: max(a.right, b.right),
            bottom: max(a.bottom, b.bottom)
        )
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
            if el.attributes["role"] == "alert" { return "alert" }
            return "none"
        }
    }

    private static func computeLive(for node: DOMNode) -> String {
        guard let el = node as? Element else { return "off" }
        let live = el.attributes["aria-live"] ?? "off"
        if live == "assertive" || live == "polite" { return live }
        return "off"
    }

    func build() {
        for childNode in node.children {
            buildInternal(childNode)
        }
        text = computeText()
        // Inline elements like <a> never get a layout object of their own;
        // borrow the union of the children's bounds instead.
        if node.layoutObject == nil, let first = children.first {
            bounds = children.dropFirst().reduce(first.bounds) {
                AccessibilityNode.union($0, $1.bounds)
            }
        }
    }

    private func buildInternal(_ childNode: DOMNode) {
        if let el = childNode as? Element, el.tag == "style" || el.tag == "script" {
            return
        }
        let child = AccessibilityNode(node: childNode, parent: self)
        if child.role != "none" || child.live != "off" {
            children.append(child)
            child.build()
        } else {
            for grandchild in childNode.children {
                buildInternal(grandchild)
            }
        }
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
