import CoreGraphics
import Foundation

public struct ResizeSettle {
    public static let delay: TimeInterval = 2.0 / 60.0

    private var width: CGFloat?
    private var changedAt: TimeInterval = 0

    public init() {}

    public mutating func note(width newWidth: CGFloat, at now: TimeInterval) {
        guard newWidth != width else { return }
        width = newWidth
        changedAt = now
    }

    public func isSettled(at now: TimeInterval) -> Bool {
        return now - changedAt >= Self.delay
    }
}
