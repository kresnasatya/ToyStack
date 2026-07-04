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
        guard opacity < 1.0 || blendMode != nil else {
            for child in children {
                if let ve = child as? VisualEffect {
                    ve.execute(context: &context)
                } else if let pc = child as? PaintCommand {
                    pc.execute(scroll: 0, context: &context)
                }
            }
            return
        }

        var layerContext = context
        layerContext.opacity = opacity
        if let mode = blendMode {
            layerContext.blendMode = mode
        }

        if children.count == 1, let layerCmd = children[0] as? DrawCompositedLayer,
            layerCmd.layer.cachedImage != nil
        {
            layerCmd.execute(scroll: 0, context: &layerContext)
            return
        }

        layerContext.drawLayer { inner in
            var innerContext = inner
            for child in self.children {
                if let ve = child as? VisualEffect {
                    ve.execute(context: &innerContext)
                } else if let pc = child as? PaintCommand {
                    pc.execute(scroll: 0, context: &innerContext)
                }
            }
        }
    }

    func clone(child: Any) -> Blend {
        return Blend(opacity: opacity, blendMode: blendMode, node: node, children: [child])
    }
}
