import CoreGraphics

public class Transform: BrowserVisualEffect {
    let translation: CGPoint?
    var isAnimated: Bool {
        guard let node = node else { return false }
        return node.animations["transform"] != nil
    }

    init(translation: CGPoint?, rect: Rect, node: DOMNode?, children: [any DisplayItem]) {
        self.translation = translation
        super.init(rect: rect, children: children, node: node)
    }

    public override func execute(renderer: any Renderer) {
        renderer.saveState()
        if let t = translation {
            renderer.translateBy(x: t.x, y: t.y)
        }

        for child in children {
            if let ve = child as? BrowserVisualEffect {
                ve.execute(renderer: renderer)
            } else if let dc = child as? DisplayCommand {
                dc.execute(scroll: 0, renderer: renderer)
            }
        }
        renderer.restoreState()
    }

    func clone(child: any DisplayItem) -> Transform {
        return Transform(translation: translation, rect: rect, node: node, children: [child])
    }

    override func map(rect: Rect) -> Rect {
        guard let t = translation else { return rect }
        return Rect(
            left: rect.left + t.x, top: rect.top + t.y, right: rect.right + t.x,
            bottom: rect.bottom + t.y)
    }

    override func unmap(rect: Rect) -> Rect {
        guard let t = translation else { return rect }
        return Rect(
            left: rect.left - t.x, top: rect.top - t.y, right: rect.right - t.x,
            bottom: rect.bottom - t.y)
    }
}
