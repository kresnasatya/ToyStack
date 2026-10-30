import CoreGraphics

// MARK: - LineLayout

@MainActor
class LineLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var fields: LayoutFieldStore = LayoutFieldStore()
    var hasDirtyDescendants: Bool = false
    var centered: Bool = false
    var hasEmbed: Bool = false
    var paintCache: LinePaintCache = LinePaintCache()
    var paintGeneration: UInt = 0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
        childrenField.setClean([])
        childrenField.setDependencies([])
        ascentField.setClean(0)
        descentField.setClean(0)
        markAncestorsDirty()
        zoomField.setDependencies([parent.zoomField])
        widthField.setDependencies([parent.widthField])
        xField.setDependencies([parent.xField])
        var yInputs: [any InvalidatableField] = [parent.yField]
        if let previous {
            yInputs.append(previous.yField)
            yInputs.append(previous.heightField)
        }
        yField.setDependencies(yInputs)
        heightField.setDependencies([ascentField, descentField])
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        return zoomField.dirty || xField.dirty || yField.dirty
            || widthField.dirty || heightField.dirty
            || ascentField.dirty || descentField.dirty
    }

    func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }
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

        setInlineInputs()
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
                shiftChildren(by: width - usedWidth)
            }

            if centered {
                let usedWidth: CGFloat = contentWidth()
                shiftChildren(by: (width - usedWidth) / 2)
            }

            heightField.set(ascentField.read(notify: heightField) + descentField.read(notify: heightField))
        })
    }

    private func setInlineInputs() {
        var ascents: [any InvalidatableField] = []
        var descents: [any InvalidatableField] = []
        for child in children {
            guard let inline = child as? InlineLayoutItem else { continue }
            ascents.append(inline.ascentField)
            descents.append(inline.descentField)
        }
        ascentField.setDependencies(ascents)
        descentField.setDependencies(descents)
    }

    private func shiftChildren(by offset: CGFloat) {
        guard offset != 0 else { return }
        let shifted: [CGFloat] = children.map { $0.x + offset }

        for (child, x) in zip(children, shifted) {
            child.x = x
        }
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
