import CoreGraphics

// MARK: - InlineExtent

struct InlineExtent: Equatable {
    var ascent: CGFloat
    var descent: CGFloat

    static let zero: InlineExtent = InlineExtent(ascent: 0, descent: 0)

    var height: CGFloat { ascent + descent }

    func union(_ other: InlineExtent) -> InlineExtent {
        return InlineExtent(ascent: max(ascent, other.ascent), descent: max(descent, other.descent))
    }
}
