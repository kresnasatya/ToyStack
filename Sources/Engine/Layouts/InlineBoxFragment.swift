// MARK: - InlineBoxFragment

/// The part of an inline element's border box that falls on one line.
/// CSS 2.1 §8.6: when the box is split across lines, its start padding and
/// border go only on its first fragment and its end ones only on its last.
struct InlineBoxFragment: Equatable {
    let dom: NodeID
    let rect: Rect
    let opens: Bool
    let closes: Bool

    /// The side edges this fragment carries, out of the element's full
    /// `edges`. CSS 2.1 §8.6: in left-to-right text the start is the left,
    /// in right-to-left text it is the right.
    func ownEdges(_ edges: EdgeInsets, direction: TextDirection) -> EdgeInsets {
        let carriesLeft: Bool = direction == .rtl ? closes : opens
        let carriesRight: Bool = direction == .rtl ? opens : closes
        return EdgeInsets(
            top: edges.top,
            right: carriesRight ? edges.right : 0,
            bottom: edges.bottom,
            left: carriesLeft ? edges.left : 0
        )
    }
}
