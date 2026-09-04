import CoreGraphics

// MARK: - LineLayout
class LineLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var minHeight: CGFloat = 0
    var centered: Bool = false
    var zoom: CGFloat = 1.0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        zoom = computeZoom(node, parentZoom: parent!.zoom)
        width = parent!.width
        x = parent!.x
        y = previous.map { $0.y + $0.height } ?? parent!.y

        for child in children { child.layout() }

        if let lastText = children.last as? TextLayout {
            lastText.width = lastText.font.measure(lastText.word)
        }

        guard !children.isEmpty else {
            height = minHeight
            return
        }

        let inlineChildren = children.compactMap { $0 as? InlineLayoutItem }
        guard !inlineChildren.isEmpty else {
            height = 0
            return
        }

        let maxAscent = inlineChildren.map(\.font.ascent).max() ?? 0
        let baseline = y + 1.25 * maxAscent

        for child in inlineChildren {
            if let el = child.node as? Element, el.tag == "sup" {
                child.y = baseline - maxAscent
            } else {
                child.y = baseline - child.font.ascent
            }
        }

        if isRTL {
            let lastChild = children.last!
            let usedWidth = lastChild.x + lastChild.width - x
            let offset = width - usedWidth

            for child in children {
                child.x += offset
            }
        }

        if centered {
            let lastChild = children.last!
            let usedWidth = lastChild.x + lastChild.width - x
            let offset = (width - usedWidth) / 2

            for child in children {
                child.x += offset
            }
        }

        let maxDescent = inlineChildren.map(\.font.descent).max() ?? 0
        height = 1.25 * (maxAscent + maxDescent)
    }

    func paint() -> [Any] {
        var cmds: [any PaintCommand] = []
        var outlineRect: Rect? = nil
        var focused: (any DOMNode)? = nil
        for child in children {
            guard let ancestor = focusVisibleInlineAncestor(child.node) else { continue }
            focused = ancestor
            let childRect = Rect(
                left: child.x, top: child.y, right: child.x + child.width,
                bottom: child.y + child.height)
                outlineRect = outlineRect?.union(childRect) ?? childRect
        }
        if let rect = outlineRect, let focused = focused {
            if let outline = cssOutline(focused, rect: rect) {
                cmds.append(outline)
            } else {
                cmds.append(DrawOutline(rect: rect, color: ringColors(node).outer, thickness: 4))
                cmds.append(DrawOutline(rect: rect, color: ringColors(node).inner, thickness: 2))
            }

        }
        return cmds
    }

    private func focusVisibleInlineAncestor(_ start: any DOMNode) -> (any DOMNode)? {
        var current: (any DOMNode)? = start.parent
        while let ancestor = current, ancestor !== node {
            if ancestor.isFocusVisible { return ancestor }
            current = ancestor.parent
        }
        return nil
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }

    func shouldPaint() -> Bool { true }
}
