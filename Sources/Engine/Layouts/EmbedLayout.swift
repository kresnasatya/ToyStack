import CoreGraphics

@MainActor
class EmbedLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    weak var parent: (any LayoutObject)?
    var previous: (any LayoutObject)?
    var fields: LayoutFieldStore = LayoutFieldStore()
    var hasDirtyDescendants: Bool = false
    var font: BrowserFont {
        get { fontField.get() }
        set { fontField.set(newValue) }
    }

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
        childrenField.setClean([])
        childrenField.setDependencies([])
        fontField.setClean(inlineDefaultFont)
        ascentField.setClean(inlineDefaultFont.ascent)
        descentField.setClean(inlineDefaultFont.descent)
        markAncestorsDirty()

        zoomField.setDependencies([parent.zoomField, node.style.field("zoom")])
        fontField.setDependencies([zoomField] + fontInputs(for: node))
        fontField.mark()
        ascentField.setDependencies([heightField])
        descentField.setDependencies([])

        var xInputs: [any InvalidatableField] = [parent.xField]
        if let previous {
            xInputs.append(previous.xField)
            xInputs.append(previous.widthField)
            if let prev = previous as? any InlineLayoutItem {
                xInputs.append(prev.fontField)
            }
        }
        xField.setDependencies(xInputs)
        var yInputs: [any InvalidatableField] = [parent.yField, ascentField]
        if let line = parent as? LineLayout {
            yInputs.append(line.ascentField)
        }
        yField.setDependencies(yInputs)
        // width and height are frozen by each subclass: their inputs differ per embed.
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        return zoomField.dirty || xField.dirty || yField.dirty
            || widthField.dirty || heightField.dirty
            || fontField.dirty || ascentField.dirty || descentField.dirty
    }

    func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }

        if zoomField.dirty {
            zoomField.set(resolvedZoom())
        }
        if fontField.dirty {
            fontField.set(fontForElement(node, zoom: zoomField.read(notify: fontField), notify: fontField))
        }

        if xField.dirty {
            if let prev = previous as? InlineLayoutItem {
                let prevX: CGFloat = prev.xField.read(notify: xField)
                let prevWidth: CGFloat = prev.widthField.read(notify: xField)
                let space: CGFloat = prev.fontField.read(notify: xField).spaceWidth
                xField.set(prevX + prevWidth + space)
            } else {
                xField.copy(from: parent!.xField)
            }
        }
    }

    func setAscentFromHeight() {
        ascentField.set(heightField.read(notify: ascentField))
        descentField.set(0)
    }

    func shouldPaint() -> Bool { true }
    func paint(into items: inout [any DisplayItem]) {}
    func paintEffects(into items: inout [any DisplayItem], from start: Int) {
        applyPaintEffects(into: &items, from: start)
    }

    func detach() {
        if let oldParent: (any LayoutObject) = parent {
            oldParent.xField.removeInvalidation(self.xField)
            oldParent.yField.removeInvalidation(self.yField)
            oldParent.zoomField.removeInvalidation(self.zoomField)
            if let oldLine = oldParent as? LineLayout {
                oldLine.ascentField.removeInvalidation(self.yField)
            }
        }
        if let oldPrevious: (any LayoutObject) = previous {
            oldPrevious.xField.removeInvalidation(self.xField)
            oldPrevious.widthField.removeInvalidation(self.xField)
            if let prev = oldPrevious as? any InlineLayoutItem {
                prev.fontField.removeInvalidation(self.xField)
            }
        }
        parent = nil
        previous = nil
    }

    func attach(to line: LineLayout, previous: (any LayoutObject)?) {
        detach()

        self.parent = line
        self.previous = previous

        zoomField.setDependencies([line.zoomField, node.style.field("zoom")])

        var xInputs: [any InvalidatableField] = [line.xField]
        if let previous {
            xInputs.append(previous.xField)
            xInputs.append(previous.widthField)
            if let prev = previous as? InlineLayoutItem {
                xInputs.append(prev.fontField)
            }
        }
        xField.setDependencies(xInputs)
        yField.setDependencies([line.yField, ascentField, line.ascentField])

        xField.mark()
        yField.mark()
    }
}
