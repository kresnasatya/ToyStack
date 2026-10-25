import CoreGraphics

@MainActor
class EmbedLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var hasDirtyDescendants: Bool = false
    var x: CGFloat = 0, y: CGFloat = 0
    var height: CGFloat = 0
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
    var font: BrowserFont = inlineDefaultFont
    var inlineAscent: CGFloat { height }
    var inlineDescent: CGFloat { 0 }

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.widthField = ProtectedField("width", node: node, parent: parent)
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.node = node;
        self.parent = parent;
        self.previous = previous
        node.layoutObject = self
    }

    func layout() {
        zoom = resolvedZoom()
        font = fontForElement(node, zoom: zoom)
        if let prev = previous as? InlineLayoutItem {
            x = prev.x + prev.font.spaceWidth + prev.width
        } else {
            x = parent!.x
        }
    }

    func shouldPaint() -> Bool { true }
    func paint(into items: inout [any DisplayItem]) {}
    func paintEffects(into items: inout [any DisplayItem], from start: Int) {
        applyPaintEffects(into: &items, from: start)
    }
}
