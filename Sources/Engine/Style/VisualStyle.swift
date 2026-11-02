import CoreGraphics

// MARK: - VisualStyle

struct VisualStyle: Equatable {
    var background: Background
    var image: Image
    var effects: Effects

    static let initial: VisualStyle = VisualStyle(
        background: Background(color: nil, image: nil, size: .auto),
        image: Image(rendering: .auto, fit: .fill),
        effects: Effects(opacity: 1, blendMode: nil, blurRadius: 0, translation: nil)
    )
}

// MARK: - Background

extension VisualStyle {
    struct Background: Equatable {
        var color: BrowserColor?
        var image: String?
        var size: BackgroundSizeSpec
    }
}

// MARK: - Image

extension VisualStyle {
    struct Image: Equatable {
        var rendering: ImageRendering
        var fit: ObjectFitKind
    }
}

// MARK: - Effects

extension VisualStyle {
    struct Effects: Equatable {
        var opacity: Double
        var blendMode: BrowserBlendMode?
        var blurRadius: CGFloat
        var translation: CGPoint?
    }
}
