import CoreGraphics

// MARK: - IntrinsicWidths

/// CSS 2.1 §10.3.5 preferred widths: `minContent` is the narrowest a box can
/// get without overflowing (its widest unbreakable piece), `maxContent` the
/// width it takes when no line has to break.
struct IntrinsicWidths: Equatable {
    var minContent: CGFloat
    var maxContent: CGFloat

    static let zero: IntrinsicWidths = IntrinsicWidths(minContent: 0, maxContent: 0)

    /// Boxes stacked in a block take the widest of each.
    func stacked(with other: IntrinsicWidths) -> IntrinsicWidths {
        return IntrinsicWidths(
            minContent: max(minContent, other.minContent),
            maxContent: max(maxContent, other.maxContent)
        )
    }

    func widened(by amount: CGFloat) -> IntrinsicWidths {
        return IntrinsicWidths(minContent: max(0, minContent + amount), maxContent: max(0, maxContent + amount))
    }
}
