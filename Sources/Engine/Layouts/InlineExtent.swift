import CoreGraphics

// MARK: - InlineExtent

/// How far an item reaches above and below the baseline; a line is as tall
/// as its tallest ascent plus its deepest descent.
struct InlineExtent: Equatable {
    var ascent: CGFloat
    var descent: CGFloat

    static let zero: InlineExtent = InlineExtent(ascent: 0, descent: 0)

    var height: CGFloat { ascent + descent }

    func union(_ other: InlineExtent) -> InlineExtent {
        return InlineExtent(ascent: max(ascent, other.ascent), descent: max(descent, other.descent))
    }
}
