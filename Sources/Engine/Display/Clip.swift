import CoreGraphics

public class Clip: BrowserVisualEffect {
    let clipRect: Rect

    init(rect: Rect, clipRect: Rect, node: DOMNode?, children: [any DisplayItem]) {
        self.clipRect = clipRect
        super.init(rect: rect, children: children, node: node)
        self.needsCompositing = false
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        renderer.clip(to: clipRect)
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
        Clip(rect: rect, clipRect: clipRect, node: node, children: children)
    }
}
