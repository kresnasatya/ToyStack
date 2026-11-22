import CoreGraphics

enum LayoutEffect: Sendable {
    case iframeViewport(node: NodeID, width: CGFloat, height: CGFloat)
    case canvasSize(node: NodeID, width: CGFloat, height: CGFloat, scale: CGFloat)
}
