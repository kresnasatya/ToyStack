import CoreGraphics

// MARK: - InkExtent

/// CSS Overflow 3 §2.2 ink overflow, vertical only: from how high to how low a
/// box and everything inside it paints, before any transform. Paint skips a
/// block whose extent misses the paint window.
struct InkExtent: Equatable {
    var top: CGFloat
    var bottom: CGFloat

    /// For a child block that has no extent yet, so its parent is never skipped.
    static let unbounded: InkExtent = InkExtent(top: -.infinity, bottom: .infinity)

    init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }

    init(_ rect: Rect) {
        self.init(top: rect.top, bottom: rect.bottom)
    }

    func union(_ other: InkExtent) -> InkExtent {
        return InkExtent(top: min(top, other.top), bottom: max(bottom, other.bottom))
    }
}
