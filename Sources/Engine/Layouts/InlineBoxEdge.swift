// MARK: - InlineBoxEdge

struct InlineBoxEdge {
    let dom: NodeID
    let side: Side

    enum Side {
        case start
        case end
    }
}
