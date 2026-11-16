// MARK: - InlineBoxEdge

/// Where an inline element with padding or border starts or ends in the
/// inline item stream. Its width is looked up from style when placed, so a
/// zoom change does not leave a stale width behind.
struct InlineBoxEdge {
    let dom: NodeID
    let side: Side

    enum Side {
        case start
        case end
    }
}
