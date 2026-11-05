import CoreGraphics
import Foundation

// MARK: - TextData

struct TextPayload {
    var word: String
    var display: String?
    var fontOverride: BrowserFont?
}

struct TextData {
    var payload: TextPayload
    var fragment: TextFragment?
    var metrics: TextMetrics
}

// MARK: - TextMetrics

struct TextMetrics {
    var width: CGFloat
    var whiteSpace: WhiteSpaceMode
    var measured: Bool = false
}
