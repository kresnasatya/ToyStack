import CoreGraphics

// MARK: - LineLayout

@MainActor
class LineLayout: LayoutObject {
    let node: any DOMNode
    weak var parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    let fields: LayoutFieldStore = LayoutFieldStore()
    var hasDirtyDescendants: Bool = false
    var centered: Bool = false
    var hasEmbed: Bool = false
    var paintCache: LinePaintCache = LinePaintCache()
    var paintGeneration: UInt = 0
    private(set) var inlineYOffset: CGFloat = 0
    private var childOriginY: CGFloat? = nil
    private var paintedChildCount: Int = -1
    private var declaredInlineChildCount: Int = -1

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
        return fields.isDirty(.zoom) || fields.isDirty(.x) || fields.isDirty(.y)
            || fields.isDirty(.width) || fields.isDirty(.height)
            || fields.isDirty(.ascent) || fields.isDirty(.descent)
    }

    func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }
        let xWasDirty: Bool = fields.isDirty(.x)
        let yWasDirty: Bool = fields.isDirty(.y)
        let zoomWasDirty: Bool = fields.isDirty(.zoom)
        let childCountChanged: Bool = children.count != declaredInlineChildCount
        var childWidthChanged: Bool = false
        for child in children where child.fields.isDirty(.width) {
            childWidthChanged = true
            break
        }
        if children.count != paintedChildCount {
            paintGeneration += 1
            paintedChildCount = children.count
        }
        zoomField.copy(from: parent!.zoomField)
        widthField.copy(from: parent!.widthField)
        xField.copy(from: parent!.xField)
        if let previous {
            yField.set(previous.yField.read(notify: yField) + previous.heightField.read(notify: yField))
        } else {
            yField.copy(from: parent!.yField)
        }

        for child in children { child.layout() }

        if children.count != declaredInlineChildCount {
            setInlineInputs()
            declaredInlineChildCount = children.count
        }

        let widthMovesChildren: Bool = centered
            || TextDirection(cssValue: node.style["direction"]) == .rtl
        let needsPlacement: Bool = xWasDirty || yWasDirty || childCountChanged
            || childWidthChanged
            || fields.isDirty(.ascent) || fields.isDirty(.descent)
            || fields.isDirty(.height) || fields.isDirty(.children)
            || widthMovesChildren

        let textOnly: Bool = children.allSatisfy({ $0 is TextLayout })
        let verticalOnly: Bool = yWasDirty && !xWasDirty && !zoomWasDirty
            && !childCountChanged && !childWidthChanged && !widthMovesChildren
            && !fields.isDirty(.ascent) && !fields.isDirty(.descent)
            && !fields.isDirty(.height) && !fields.isDirty(.children)
            && textOnly && childOriginY != nil

        if verticalOnly, let childOriginY {
            profiler.count("layout.line.place.verticalOnly")
            profiler.measure("layout.line.place.vertical", {
                inlineYOffset = yField.get() - childOriginY
            })
            return
        }

        guard needsPlacement else {
            profiler.count("layout.line.place.skipped")
            return
        }

        profiler.count("layout.line.place.placed")
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

            var nextX: CGFloat = xField.get()
            var previousFont: BrowserFont? = nil
            for child in inlineChildren {
                if let previousFont, child is EmbedLayout {
                    nextX += previousFont.spaceWidth
                }
                child.xField.set(nextX)
                nextX += child.widthField.get()
                previousFont = child.fontField.get()
            }

            let lineY: CGFloat = yField.get()
            let baseline: CGFloat = lineY + ascentField.get()
            for child in inlineChildren {
                if let el = child.node as? Element, el.tag == "sup" {
                    child.yField.set(baseline - maxAscent)
                } else {
                    child.yField.set(baseline - child.ascentField.get())
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
            childOriginY = yField.get()
            inlineYOffset = 0
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
        paintGeneration += 1
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

    func paint(into items: inout [DisplayOp]) {
        var outlineRect: Rect? = nil
        var focused: (any DOMNode)? = nil
        for child in children {
            guard let ancestor = focusVisibleInlineAncestor(child.node) else { continue }
            focused = ancestor
            let childRect: Rect = child.selfRect()
            outlineRect = outlineRect?.union(childRect) ?? childRect
        }
        if let rect = outlineRect, let focused = focused {
            if let outline = DisplayOp.fromStyle(focused, rect: rect) {
                items.append(outline)
            } else {
                items.append(.outline(rect: rect, color: BrowserColor(cssName: focusRingColors(node).outer), width: 4))
                items.append(.outline(rect: rect, color: BrowserColor(cssName: focusRingColors(node).inner), width: 2))
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
