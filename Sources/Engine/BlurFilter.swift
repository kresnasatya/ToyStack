import SwiftUI

public class BlurFilter: Engine.VisualEffect {
    let radius: CGFloat

    init(radius: CGFloat, node: DOMNode?, children: [Any]) {
        self.radius = radius

        var combinedRect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for child in children {
            if let ve = child as? Engine.VisualEffect {
                combinedRect = combinedRect.union(ve.rect)
            } else if let pc = child as? PaintCommand {
                combinedRect = combinedRect.union(pc.rect)
            }
        }

        super.init(rect: combinedRect, children: children, node: node)
        // A blurred layer must be composited in isolation - same rule as opacity < 1
        self.needsCompositing = radius > 0 || self.needsCompositing
    }

    func clone(child: Any) -> BlurFilter {
        return BlurFilter(radius: radius, node: node, children: [child])
    }

    public override func execute(context: inout GraphicsContext) {
        context.drawLayer(content: { inner in
            var innerCtx = inner
            innerCtx.addFilter(.blur(radius: radius))
            for child in self.children {
                if let ve = child as? Engine.VisualEffect {
                    ve.execute(context: &innerCtx)
                } else if let pc = child as? PaintCommand {
                    pc.execute(scroll: 0, context: &innerCtx)
                }
            }
        })
    }
}
