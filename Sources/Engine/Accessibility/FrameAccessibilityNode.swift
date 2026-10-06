import CoreGraphics

// MARK: - FrameAccessibilityNode
@MainActor
final class FrameAccessibilityNode: AccessibilityNode {
    private var frame: Frame? { (node as? Element)?.frame }
    private var border: CGFloat { node.layoutObject?.scaled(1) ?? 1 }

    override func build() {
        guard let frame, frame.loaded else { return }
        buildInternal(frame.nodes)
    }

    override func hitTest(x: CGFloat, y: CGFloat) -> AccessibilityNode? {
        guard bounds.containsPoint(x, y) else { return nil }
        let newX: CGFloat = x - bounds.left - border
        let newY: CGFloat = y - bounds.top - border + (frame?.scroll ?? 0)
        var result: AccessibilityNode? = self
        for child in children {
            if let hit = child.hitTest(x: newX, y: newY) { result = hit }
        }
        return result
    }

    override func mapToParent(_ rect: inout Rect) {
        let scroll: CGFloat = frame?.scroll ?? 0
        rect = Rect(
            left: rect.left + bounds.left,
            top: rect.top + bounds.top - scroll,
            right: rect.right + bounds.left,
            bottom: rect.bottom + bounds.top - scroll
        )
        rect = rect.intersect(bounds)
    }
}
