import CoreGraphics

public class BrowserVisualEffect {
    public var rect: Rect
    var children: [DisplayOp]
    weak var node: DOMNode?

    init(rect: Rect, children: [DisplayOp], node: DOMNode? = nil) {
        self.rect = rect
        self.children = children
        self.node = node
    }

    public func execute(renderer: any Renderer) {}

    func map(rect: Rect) -> Rect { return rect }

    func unmap(rect: Rect) -> Rect { return rect }

    func clone(children: [DisplayOp]) -> BrowserVisualEffect {
        fatalError("\(type(of: self)) must be implement clone(children:)")
    }
}

@MainActor
func paintBrowserVisualEffects(style: PaintEffectStyle, node: DOMNode, items: [DisplayOp], rect: Rect) -> [DisplayOp] {
    var displayItems: [DisplayOp] = items
    if style.blurRadius > 0 {
        displayItems = [.effect(BlurFilter(radius: style.blurRadius, node: node, children: displayItems))]
    }

    let blend: Blend = Blend(
        opacity: style.opacity,
        blendMode: style.blendMode,
        node: node,
        children: displayItems
    )

    let transform: Transform = Transform(
        translation: style.translation,
        rect: rect,
        node: node,
        children: [.effect(blend)]
    )

    return [.effect(transform)]
}

@MainActor
func paintBrowserVisualEffects(node: DOMNode, items: [DisplayOp], rect: Rect) -> [DisplayOp] {
    guard let style: PaintEffectStyle = paintEffectStyle(node: node) else { return items }
    return paintBrowserVisualEffects(style: style, node: node, items: items, rect: rect)
}

