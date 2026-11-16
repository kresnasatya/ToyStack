import CoreGraphics

// MARK: - InlineFlowEvent

/// One step across a line, in order: a child takes its width, and an inline
/// element's start or end takes the room of its padding and border.
/// `opens` and `closes` are false when the element continues from the line
/// before or onto the line after.
enum InlineFlowEvent: Equatable {
    case child
    case open(dom: NodeID, width: CGFloat, opens: Bool)
    case close(dom: NodeID, width: CGFloat, closes: Bool)
}
