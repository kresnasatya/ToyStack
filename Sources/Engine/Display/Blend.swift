import CoreGraphics

public class Blend: BrowserVisualEffect {
    let opacity: Double
    let blendMode: BrowserBlendMode?

    init(opacity: Double, blendMode: BrowserBlendMode?, node: DOMNode?, children: [any DisplayItem]) {
        self.opacity = opacity
        self.blendMode = blendMode

        var combinedRect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for child in children {
            if let ve = child as? BrowserVisualEffect {
                combinedRect = combinedRect.union(ve.rect)
            } else if let dc = child as? DisplayCommand {
                combinedRect = combinedRect.union(dc.rect)
            }
        }

        super.init(rect: combinedRect, children: children, node: node)

        self.needsCompositing = opacity < 1.0 || blendMode != nil || self.needsCompositing
    }

    public override func execute(renderer: any Renderer) {
        guard opacity < 1.0 || blendMode != nil else {
            for child in children {
                if let ve = child as? BrowserVisualEffect {
                    ve.execute(renderer: renderer)
                } else if let dc = child as? DisplayCommand {
                    dc.execute(scroll: 0, renderer: renderer)
                }
            }
            return
        }

        renderer.drawLayer(LayerOptions(opacity: opacity, blendMode: blendMode)) { r in
            for child in self.children {
                if let ve = child as? BrowserVisualEffect {
                    ve.execute(renderer: r)
                } else if let dc = child as? DisplayCommand {
                    dc.execute(scroll: 0, renderer: r)
                }
            }
        }
    }

    func clone(child: any DisplayItem) -> Blend {
        return Blend(opacity: opacity, blendMode: blendMode, node: node, children: [child])
    }
}
