import CoreGraphics
import Foundation

/// Identifies the viewport a background layout was started for.
struct LayoutJobKey: Equatable, Sendable {
    let width: CGFloat
    let zoom: CGFloat

    func isStale(currentWidth: CGFloat, currentZoom: CGFloat) -> Bool {
        return abs(width - currentWidth) > 0.5 || abs(zoom - currentZoom) > 0.0001
    }
}
