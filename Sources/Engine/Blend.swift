import CoreGraphics

public class Blend: VisualEffect {
    let opacity: Double
    let blendMode: EngineBlendMode?

    init(opacity: Double, blendMode: EngineBlendMode?, node: DOMNode?, children: [Any]) {
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

    public override func execute(renderer: any Renderer) {
        guard opacity < 1.0 || blendMode != nil else {
            for child in children {
                if let ve = child as? VisualEffect {
                    ve.execute(renderer: renderer)
                } else if let pc = child as? PaintCommand {
                    pc.execute(scroll: 0, renderer: renderer)
                }
            }
            return
        }

        renderer.drawLayer(LayerOptions(opacity: opacity, blendMode: blendMode)) { r in
            for child in self.children {
                if let ve = child as? VisualEffect {
                    ve.execute(renderer: r)
                } else if let pc = child as? PaintCommand {
                    pc.execute(scroll: 0, renderer: r)
                }
            }
        }
    }

    func clone(child: Any) -> Blend {
        return Blend(opacity: opacity, blendMode: blendMode, node: node, children: [child])
    }
}
