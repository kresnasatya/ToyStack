import CoreGraphics
import Foundation

// MARK: - TextData

struct TextData {
    var word: String
    var display: String?
    var fontOverride: BrowserFont?
    var metrics: TextMetrics
}

// MARK: - TextMetrics

struct TextMetrics {
    var width: CGFloat
    var whiteSpace: WhiteSpaceMode
    var measured: Bool = false
}
