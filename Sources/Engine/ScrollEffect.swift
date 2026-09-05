import CoreGraphics

public class ScrollEffect: Engine.VisualEffect {
    let clipRect: Rect
    var scrollOffset: CGFloat

    init(rect: Rect, scrollOffset: CGFloat, node: DOMNode?, children: [Any]) {
        self.clipRect = rect
        self.scrollOffset = scrollOffset
        super.init(rect: rect, children: children, node: node)
        self.needsCompositing = false
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        let cgRect = CGRect(
            x: clipRect.left, y: clipRect.top,
            width: clipRect.right - clipRect.left,
            height: clipRect.bottom - clipRect.top
        )
        renderer.clip(to: cgRect)
        renderer.translateBy(x: 0, y: -scrollOffset)
        for child in children {
            if let ve = child as? Engine.VisualEffect {
                ve.execute(renderer: renderer)
            } else if let pc = child as? PaintCommand {
                pc.execute(scroll: 0, renderer: renderer)
            }
        }
        renderer.restoreState()
    }

    func clone(child: Any) -> ScrollEffect {
        ScrollEffect(rect: clipRect, scrollOffset: scrollOffset, node: node, children: [child])
    }
}
