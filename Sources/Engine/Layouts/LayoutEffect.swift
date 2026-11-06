import CoreGraphics

/// DOM writes a layout pass asks for but cannot perform itself.
///
/// Layout computes sizes from values; the frame applies these on the main
/// actor after the pass, where the document is reachable.
enum LayoutEffect: Sendable {
    case iframeViewport(node: NodeID, width: CGFloat, height: CGFloat)
    case canvasSize(node: NodeID, width: CGFloat, height: CGFloat, scale: CGFloat)
}
