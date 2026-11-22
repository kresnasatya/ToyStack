import CoreGraphics

// MARK: - IntrinsicWidths

/// CSS 2.1 §10.3.5 preferred widths: `minContent` is the preferred minimum width, the
/// narrowest a box gets when every possible line break is taken (its widest unbreakable
/// piece), and `maxContent` the preferred width, where lines break only at explicit breaks.
struct IntrinsicWidths: Equatable {
    var minContent: CGFloat
    var maxContent: CGFloat

    static let zero: IntrinsicWidths = IntrinsicWidths(minContent: 0, maxContent: 0)

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
