import CoreGraphics
import Foundation

/// Tells whether the view width has stopped changing.
///
/// A window drag delivers a new width about every display frame. When no
/// width change arrives for `delay`, the drag has paused or ended, and the
/// last layout is the one worth showing.
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
