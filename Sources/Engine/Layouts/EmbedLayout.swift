import CoreGraphics

@MainActor
class EmbedLayout: LayoutObject, InlineLayoutItem {
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
    let heightField: ProtectedField<CGFloat>
    var height: CGFloat {
        get { heightField.get() }
        set { heightField.set(newValue) }
    }
    let widthField: ProtectedField<CGFloat>
    var width: CGFloat {
        get { widthField.get() }
        set { widthField.set(newValue) }
    }
    let zoomField: ProtectedField<CGFloat>
    var zoom: CGFloat {
        get { zoomField.get() }
        set { zoomField.set(newValue) }
    }
    let fontField: ProtectedField<BrowserFont>
    var font: BrowserFont {
        get { fontField.get() }
        set { fontField.set(newValue) }
    }
    let ascentField: ProtectedField<CGFloat>
    let descentField: ProtectedField<CGFloat>

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.widthField = ProtectedField("width", node: node, parent: parent)
        self.heightField = ProtectedField("height", node: node, parent: parent)
        self.xField = ProtectedField("x", node: node, parent: parent)
        self.yField = ProtectedField("y", node: node, parent: parent)
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.fontField = ProtectedField(
            owner: FieldOwner(name: "font", node: node, parent: parent),
            equals: { lhs, rhs in CFEqual(lhs.ctFont, rhs.ctFont) },
            cleanValue: inlineDefaultFont
        )
        self.ascentField = ProtectedField(
            "ascent",
            cleanValue: inlineDefaultFont.ascent,
            node: node,
            parent: parent
        )
        self.descentField = ProtectedField(
            "descent",
            cleanValue: inlineDefaultFont.descent,
            node: node,
            parent: parent
        )
        self.node = node;
        self.parent = parent;
        self.previous = previous
        node.layoutObject = self
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants { return true }
        return zoomField.dirty || xField.dirty || yField.dirty
            || widthField.dirty || heightField.dirty
            || fontField.dirty || ascentField.dirty || descentField.dirty
    }

    func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }
        zoomField.set(resolvedZoom())
        fontField.set(fontForElement(node, zoom: zoomField.read(notify: fontField), notify: fontField))

        if let prev = previous as? InlineLayoutItem {
            let prevX: CGFloat = prev.xField.read(notify: xField)
            let prevWidth: CGFloat = prev.widthField.read(notify: xField)
            let space: CGFloat = prev.fontField.read(notify: xField).spaceWidth
            xField.set(prevX + prevWidth + space)
        } else {
            xField.copy(from: parent!.xField)
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
}
