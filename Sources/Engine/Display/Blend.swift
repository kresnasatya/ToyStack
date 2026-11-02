import CoreGraphics

public class Blend: BrowserVisualEffect {
    let opacity: Double
    let blendMode: BrowserBlendMode?

    init(opacity: Double, blendMode: BrowserBlendMode?, node: DOMNode?, children: [DisplayOp]) {
        self.opacity = opacity
        self.blendMode = blendMode

        var combinedRect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for child in children {
            combinedRect = combinedRect.union(child.rect)
        }

        super.init(rect: combinedRect, children: children, node: node)
    }

    public override func execute(renderer: any Renderer) {
        guard opacity < 1.0 || blendMode != nil else {
            for child in children {
                child.execute(renderer: renderer)
            }
            return
        }

        renderer.drawLayer(LayerOptions(opacity: opacity, blendMode: blendMode)) { r in
            for child in self.children {
                child.execute(renderer: r)
            }
        }
    }

    override func clone(children: [DisplayOp]) -> BrowserVisualEffect {
        return Blend(opacity: opacity, blendMode: blendMode, node: node, children: children)
    }
}
