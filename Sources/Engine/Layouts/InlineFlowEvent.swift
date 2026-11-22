import CoreGraphics

// MARK: - InlineFlowEvent

enum InlineFlowEvent: Equatable {
    case child
    case open(dom: NodeID, width: CGFloat, opens: Bool)
    case close(dom: NodeID, width: CGFloat, closes: Bool)
}
