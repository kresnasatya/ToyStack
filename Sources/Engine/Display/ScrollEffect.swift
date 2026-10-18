import CoreGraphics

public class ScrollEffect: BrowserVisualEffect {
    let shape: ClipShape
    var scrollOffset: CGFloat

    init(shape: ClipShape, scrollOffset: CGFloat, node: DOMNode?, children: [any DisplayItem]) {
        self.shape = shape
        self.scrollOffset = scrollOffset
        super.init(rect: shape.rect, children: children, node: node)
        self.needsCompositing = false
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
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
        ScrollEffect(shape: shape, scrollOffset: scrollOffset, node: node, children: children)
    }
}
