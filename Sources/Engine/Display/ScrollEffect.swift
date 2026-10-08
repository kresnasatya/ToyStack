import CoreGraphics

public class ScrollEffect: BrowserVisualEffect {
    let clipRect: Rect
    var scrollOffset: CGFloat

    init(rect: Rect, scrollOffset: CGFloat, node: DOMNode?, children: [any DisplayItem]) {
        self.clipRect = rect
        self.scrollOffset = scrollOffset
        super.init(rect: rect, children: children, node: node)
        self.needsCompositing = false
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        renderer.clip(to: clipRect)
        renderer.translateBy(x: 0, y: -scrollOffset)
        for child in children {
            if let ve = child as? BrowserVisualEffect {
                ve.execute(renderer: renderer)
            } else if let dc = child as? DisplayCommand {
                dc.execute(scroll: 0, renderer: renderer)
            }
        }
        renderer.restoreState()
    }

    override func clone(children: [any DisplayItem]) -> BrowserVisualEffect {
        ScrollEffect(rect: clipRect, scrollOffset: scrollOffset, node: node, children: children)
    }
}
