import SwiftUI

// Clip and vertically offsets its children to implement overflow:scroll
// Rendered by BrowserView exactly like Blend/Transform: ve.execute(context:).
// The incoming context already has the page-level translateBy applied,
// so document coordinates map directly to screen coordinates here.
public class ScrollEffect: Engine.VisualEffect {
    let clipRect: Rect
    var scrollOffset: CGFloat

    init(rect: Rect, scrollOffset: CGFloat, node: DOMNode?, children: [Any]) {
        self.clipRect = rect
        self.scrollOffset = scrollOffset
        super.init(rect: rect, children: children, node: node)
        // false: let PaintCommand children be composited normally.
        // paintDrawList() reconstructs this wrapper via clone().
        self.needsCompositing = false
    }

    // Clips to element bounds then shifts content up by scrollOffset.
    public override func execute(context: inout GraphicsContext) {
        var ctx = context  // value copy: own clip state, shared canvas
        let cgRect = CGRect(
            x: clipRect.left, y: clipRect.top,
            width: clipRect.right - clipRect.left,
            height: clipRect.bottom - clipRect.top
        )
        ctx.clip(to: Path(cgRect))
        ctx.translateBy(x: 0, y: -scrollOffset)
        for child in children {
            if let ve = child as? Engine.VisualEffect {
                ve.execute(context: &ctx)
            } else if let pc = child as? PaintCommand {
                pc.execute(scroll: 0, context: &ctx)
            }
        }
    }

    // Called by Browser.paintDrawList() to wrap each CompositedLayer.
    func clone(child: Any) -> ScrollEffect {
        ScrollEffect(rect: clipRect, scrollOffset: scrollOffset, node: node, children: [child])
    }
}
