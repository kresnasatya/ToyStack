import Foundation

/// Caps the pixels one present may upload so a new layout generation can be
/// staged across several composites without exposing an incomplete frame.
public struct PresentUploadBudget: Sendable {
    public let pixels: Int
    public private(set) var usedPixels: Int = 0

    public init(pixels: Int) {
        self.pixels = max(0, pixels)
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
}
