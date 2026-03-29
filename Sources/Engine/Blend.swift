import SwiftUI

public class Blend: VisualEffect {
    let opacity: Double
    let blendMode: GraphicsContext.BlendMode?

    init(opacity: Double, blendMode: GraphicsContext.BlendMode?, node: DOMNode?, children: [Any]) {
        self.opacity = opacity
        self.blendMode = blendMode

        var combinedRect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for child in children {
            if let ve = child as? VisualEffect {
                combinedRect = combinedRect.union(ve.rect)
            } else if let pc = child as? PaintCommand {
                combinedRect = combinedRect.union(pc.rect)
            }
        }

        super.init(rect: combinedRect, children: children, node: node)

        self.needsCompositing = opacity < 1.0 || blendMode != nil || self.needsCompositing
    }

    public override func execute(context: inout GraphicsContext) {
        var layerContext = context
        layerContext.opacity = opacity
        if let mode = blendMode {
            layerContext.blendMode = mode
        }
        for child in children {
            if let ve = child as? VisualEffect {
                ve.execute(context: &layerContext)
            } else if let pc = child as? PaintCommand {
                pc.execute(scroll: 0, context: &layerContext)
            }
        }
    }

    func clone(child: Any) -> Blend {
        return Blend(opacity: opacity, blendMode: blendMode, node: node, children: [child])
    }
}
