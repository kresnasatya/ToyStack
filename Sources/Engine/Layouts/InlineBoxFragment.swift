// MARK: - InlineBoxFragment

/// The part of an inline element's border box that falls on one line.
/// CSS 2.1 §8.6: when the box is split across lines, the left padding and
/// border go only on its first fragment and the right ones only on its last.
struct InlineBoxFragment: Equatable {
    let dom: NodeID
    /// Relative to the line's origin, so moving the line moves the fragment.
    let rect: Rect
    let opens: Bool
    let closes: Bool
}
