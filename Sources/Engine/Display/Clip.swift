import CoreGraphics

public class Clip: BrowserVisualEffect {
    let shape: ClipShape

    init(rect: Rect, shape: ClipShape, node: DOMNode?, children: [DisplayOp]) {
        self.shape = shape
        super.init(rect: rect, children: children, node: node)
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
        for child in children {
            child.execute(renderer: renderer)
        }
        renderer.restoreState()
    }

    override func clone(children: [DisplayOp]) -> BrowserVisualEffect {
        Clip(rect: rect, shape: shape, node: node, children: children)
    }
}
