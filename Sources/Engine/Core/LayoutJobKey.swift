import CoreGraphics
import Foundation

/// What a background layout was started for: the viewport, and the scroll
/// target revision its tree reflects.
struct LayoutJobKey: Equatable, Sendable {
    let size: CGSize
    let zoom: CGFloat
    let targetsRevision: UInt64

    /// True when the viewport moved on while the job ran. The result is still
    /// a complete layout for `size`, but another pass must follow.
    func isStale(currentSize: CGSize, currentZoom: CGFloat) -> Bool {
        return abs(size.width - currentSize.width) > 0.5
            || abs(size.height - currentSize.height) > 0.5
            || abs(zoom - currentZoom) > 0.0001
    }
}
