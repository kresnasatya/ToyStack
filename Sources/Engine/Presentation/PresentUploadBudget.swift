import Foundation

public struct PresentUploadBudget: Sendable {
    public static let generationPixels: Int = 2_000_000

    public let pixels: Int
    public private(set) var usedPixels: Int = 0

    public init(pixels: Int) {
        self.pixels = max(0, pixels)
    }

    public static func generation(resizeSettled: Bool) -> PresentUploadBudget {
        return PresentUploadBudget(pixels: resizeSettled ? 2 * generationPixels : generationPixels)
    }

    public mutating func take(pixels itemPixels: Int) -> Bool {
        guard itemPixels > 0 else { return false }
        if usedPixels == 0 || usedPixels + itemPixels <= pixels {
            usedPixels += itemPixels
            return true
        }
        return false
    }

    public func admitsAll(pixels items: [Int]) -> Bool {
        var trial: PresentUploadBudget = self
        return items.allSatisfy { trial.take(pixels: $0) }
    }
}
