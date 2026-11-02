import CoreGraphics

public class BlurFilter: BrowserVisualEffect {
    let radius: CGFloat

    init(radius: CGFloat, node: DOMNode?, children: [DisplayOp]) {
        self.radius = radius

        var combinedRect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for child in children {
            combinedRect = combinedRect.union(child.rect)
        }

        super.init(rect: combinedRect, children: children, node: node)
    }

    override func clone(children: [DisplayOp]) -> BrowserVisualEffect {
        return BlurFilter(radius: radius, node: node, children: children)
    }

    public override func execute(renderer: any Renderer) {
        renderer.drawLayer(LayerOptions(blur: radius)) { r in
            for child in self.children {
                child.execute(renderer: r)
            }
        }
    }
}
