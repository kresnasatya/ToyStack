import CoreGraphics

@MainActor
class EmbedLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var x: CGFloat = 0, y: CGFloat = 0, width: CGFloat = 0, height: CGFloat = 0
    var zoom: CGFloat = 1.0
    var font: BrowserFont = inlineDefaultFont
    var inlineAscent: CGFloat { height }
    var inlineDescent: CGFloat { 0 }

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
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
    func paint() -> [any DisplayItem] { [] }
}
