import Foundation

/// Caps the pixels one present may upload so a new layout generation can be
/// staged across several composites without exposing an incomplete frame.
public struct PresentUploadBudget: Sendable {
    /// Pixel budget for staging one new layer generation.
    public static let generationPixels: Int = 2_000_000

    public let pixels: Int
    public private(set) var usedPixels: Int = 0

    public init(pixels: Int) {
        self.pixels = max(0, pixels)
    }

    /// Budget for one present of a staged generation. Whenever the window
    /// width is not changing, a generation gets twice the pixels: after a
    /// drag, a 1440-wide window (132 tiles) goes up in 3 presents instead of
    /// 5. This also covers generations at an unchanged width (page load,
    /// style change, animation). A 30-tile commit costs ~6 ms (median), but
    /// a 60-tile one can pass one display frame at p95. While the width
    /// moves, presents stay light so previews keep up. The skip check and the
    /// upload of one present must use the same budget, or the check would
    /// drop an upload that this present finishes.
    public static func generation(resizeSettled: Bool) -> PresentUploadBudget {
        return PresentUploadBudget(pixels: resizeSettled ? 2 * generationPixels : generationPixels)
    }

    /// Returns true when this item fits, or when it is the first item in the
    /// batch. One oversized tile must still make progress.
    public mutating func take(pixels itemPixels: Int) -> Bool {
        guard itemPixels > 0 else { return false }
        if usedPixels == 0 || usedPixels + itemPixels <= pixels {
            usedPixels += itemPixels
            return true
        }
        return false
    }

    /// Returns true when one present with this budget uploads every item, so
    /// an upload with these items left finishes in that present. Does not
    /// spend the budget.
    public func admitsAll(pixels items: [Int]) -> Bool {
        var trial: PresentUploadBudget = self
        return items.allSatisfy { trial.take(pixels: $0) }
    }
}
