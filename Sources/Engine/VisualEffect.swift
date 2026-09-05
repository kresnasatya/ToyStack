import CoreGraphics

public class VisualEffect {
    var rect: Rect
    var children: [Any]
    weak var node: DOMNode?
    var needsCompositing: Bool
    weak var parent: VisualEffect?

    init(rect: Rect, children: [Any], node: DOMNode? = nil) {
        self.rect = rect
        self.children = children
        self.node = node
        self.needsCompositing = children.compactMap({
            $0 as? VisualEffect
        })
        .contains(where: {
            $0.needsCompositing
        })
    }

    public func execute(renderer: any Renderer) {}

    func map(rect: Rect) -> Rect { return rect }

    func unmap(rect: Rect) -> Rect { return rect }
}
