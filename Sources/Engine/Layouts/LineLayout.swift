import CoreGraphics

// MARK: - LineLayout

@MainActor
class LineLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var hasDirtyDescendants: Bool = false
    let xField: ProtectedField<CGFloat>
    var x: CGFloat {
        get { xField.get() }
        set { xField.set(newValue) }
    }
    let yField: ProtectedField<CGFloat>
    var y: CGFloat {
        get { yField.get() }
        set { yField.set(newValue) }
    }
    let widthField: ProtectedField<CGFloat>
    var width: CGFloat {
        get { widthField.get() }
        set { widthField.set(newValue) }
    }
    let heightField: ProtectedField<CGFloat>
    var height: CGFloat {
        get { heightField.get() }
        set { heightField.set(newValue) }
    }
    var centered: Bool = false
    let zoomField: ProtectedField<CGFloat>
    var zoom: CGFloat {
        get { zoomField.get() }
        set { zoomField.set(newValue) }
    }
    let ascentField: ProtectedField<CGFloat>
    let descentField: ProtectedField<CGFloat>
    var hasEmbed: Bool = false
    var paintCache: LinePaintCache = LinePaintCache()
    var paintGeneration: UInt = 0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.widthField = ProtectedField("width", node: node, parent: parent)
        self.heightField = ProtectedField("height", node: node, parent: parent)
        self.xField = ProtectedField("x", node: node, parent: parent)
        self.yField = ProtectedField("y", node: node, parent: parent)
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.ascentField = ProtectedField("ascent", cleanValue: 0, node: node, parent: parent)
        self.descentField = ProtectedField("descent", cleanValue: 0, node: node, parent: parent)
        self.node = node
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        if !layoutNeeded() { return }
        paintGeneration += 1
        zoomField.copy(from: parent!.zoomField)
        widthField.copy(from: parent!.widthField)
        xField.copy(from: parent!.xField)
        if let previous {
            yField.set(previous.yField.read(notify: yField) + previous.heightField.read(notify: yField))
        } else {
            yField.copy(from: parent!.yField)
        }

        for child in children { child.layout() }

        profiler.measure("layout.line.place", {

            guard !children.isEmpty else {
                ascentField.set(0)
                descentField.set(0)
                heightField.set(0)
                return
            }

            let inlineChildren: [any InlineLayoutItem] = children.compactMap {
                $0 as? InlineLayoutItem
            }
            guard !inlineChildren.isEmpty else {
                heightField.set(0)
                return
            }

            let maxAscent: CGFloat = inlineChildren.map {
                $0.ascentField.read(notify: ascentField)
            }.max() ?? 0
            ascentField.set(maxAscent)
            let maxDescent: CGFloat = inlineChildren.map {
                $0.descentField.read(notify: descentField)
            }.max() ?? 0
            descentField.set(maxDescent)

            for child in inlineChildren {
                let lineY: CGFloat = yField.read(notify: child.yField)
                let baseline: CGFloat = lineY + ascentField.read(notify: child.yField)
                if let el = child.node as? Element, el.tag == "sup" {
                    child.yField.set(baseline - maxAscent)
                } else {
                    let ascent: CGFloat = child.ascentField.read(notify: child.yField)
                    child.yField.set(baseline - ascent)
                }
            }

            for child in children where !child.children.isEmpty {
                child.layout()
            }

            if TextDirection(cssValue: node.style["direction"]) == .rtl {
                let usedWidth: CGFloat = contentWidth()
                let offset: CGFloat = width - usedWidth

                for child in children {
                    child.x += offset
                }
            }

            if centered {
                let usedWidth: CGFloat = contentWidth()
                let offset: CGFloat = (width - usedWidth) / 2

                for child in children {
                    child.x += offset
                }
            }

            heightField.set(ascentField.read(notify: heightField) + descentField.read(notify: heightField))
        })
    }

    private func contentWidth() -> CGFloat {
        guard let last = children.last else { return 0 }
        let trailing: CGFloat = (last as? TextLayout)?.textWidth ?? last.width
        return last.x + trailing - x
    }

    func canCachePaint() -> Bool {
        return !hasEmbed
    }

    func paint(into items: inout [any DisplayItem]) {
        var outlineRect: Rect? = nil
        var focused: (any DOMNode)? = nil
        for child in children {
            guard let ancestor = focusVisibleInlineAncestor(child.node) else { continue }
            focused = ancestor
            let childRect: Rect = Rect(
                left: child.x, top: child.y, right: child.x + child.width,
                bottom: child.y + child.height)
                outlineRect = outlineRect?.union(childRect) ?? childRect
        }
        if let rect = outlineRect, let focused = focused {
            if let outline = DrawOutline.fromStyle(focused, rect: rect) {
                items.append(outline)
            } else {
                items.append(DrawOutline(rect: rect, color: focusRingColors(node).outer, thickness: 4))
                items.append(DrawOutline(rect: rect, color: focusRingColors(node).inner, thickness: 2))
            }

        }
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
