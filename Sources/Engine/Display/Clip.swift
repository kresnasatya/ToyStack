import CoreGraphics

public class Clip: BrowserVisualEffect {
    let shape: ClipShape

    init(rect: Rect, shape: ClipShape, node: DOMNode?, children: [any DisplayItem]) {
        self.shape = shape
        super.init(rect: rect, children: children, node: node)
        self.needsCompositing = false
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
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
        Clip(rect: rect, shape: shape, node: node, children: children)
    }
}
