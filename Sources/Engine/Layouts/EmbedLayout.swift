import CoreGraphics

@MainActor
class EmbedLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    weak var parent: (any LayoutObject)?
    var previous: (any LayoutObject)?
    let fields: LayoutFieldStore = LayoutFieldStore()
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

        zoomField.setDependencies([parent.zoomField, node.style.field(.zoom)])
        fontField.setDependencies([zoomField] + fontInputs(for: node))
        fontField.mark()
        ascentField.setDependencies([heightField])
        descentField.setDependencies([])
        // Position is assigned by the containing line; there are no inputs.
        xField.setDependencies([])
        yField.setDependencies([])
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        return fields.isDirty(.zoom) || fields.isDirty(.width) || fields.isDirty(.height)
            || fields.isDirty(.font) || fields.isDirty(.ascent) || fields.isDirty(.descent)
    }

    func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }

        if fields.isDirty(.zoom) {
            zoomField.set(resolvedZoom())
        }
        if fields.isDirty(.font) {
            fontField.set(fontForElement(node, zoom: zoomField.read(notify: fontField), notify: fontField))
        }
    }

    func setAscentFromHeight() {
        ascentField.set(heightField.read(notify: ascentField))
        descentField.set(0)
    }

    func shouldPaint() -> Bool { true }
    func paint(into items: inout [DisplayOp]) {}
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

        zoomField.setDependencies([line.zoomField, node.style.field(.zoom)])
    }
}
