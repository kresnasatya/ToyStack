import CoreGraphics
import Foundation

// MARK: - EmbedData

enum EmbedData {
    case image(ImageData)
    case input
    case button(ButtonData)
    case iframe
    case canvas
}

// MARK: - ImageData

struct ImageData {
    var imageHeight: CGFloat
}

// MARK: - ButtonData

struct ButtonData {
    var cursorX: CGFloat
}
