import CoreGraphics
import Foundation

struct LayoutJobKey: Equatable, Sendable {
    let size: CGSize
    let zoom: CGFloat
    let targetsRevision: UInt64

    func isStale(currentSize: CGSize, currentZoom: CGFloat) -> Bool {
        return abs(size.width - currentSize.width) > 0.5
            || abs(size.height - currentSize.height) > 0.5
            || abs(zoom - currentZoom) > 0.0001
    }
}
