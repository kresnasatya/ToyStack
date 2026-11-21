import CoreGraphics
import Foundation

// MARK: - DocumentData

struct DocumentData {
    var pageZoom: CGFloat
    var clearingBlocks: Set<LayoutID> = []
}
