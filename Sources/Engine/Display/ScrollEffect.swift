import CoreGraphics

public class ScrollEffect: BrowserVisualEffect {
    let shape: ClipShape
    var scrollOffset: CGFloat

    init(shape: ClipShape, scrollOffset: CGFloat, node: DOMNode?, children: [DisplayOp]) {
        self.shape = shape
        self.scrollOffset = scrollOffset
        super.init(rect: shape.rect, children: children, node: node)
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
        renderer.translateBy(x: 0, y: -scrollOffset)
        for child in children {
            child.execute(renderer: renderer)
        }
        renderer.restoreState()
    }

    override func clone(children: [DisplayOp]) -> BrowserVisualEffect {
        ScrollEffect(shape: shape, scrollOffset: scrollOffset, node: node, children: children)
    }
}
