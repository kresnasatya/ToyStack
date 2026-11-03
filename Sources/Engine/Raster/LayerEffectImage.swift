import CoreGraphics

/// The last effect bitmap generated for a layer.
public struct LayerEffectImage {
    var image: CGImage?
    var key: EffectImageKey?

    init() {
        self.image = nil
        self.key = nil
    }
}

// MARK: - EffectImageKey

public struct EffectImageKey: Equatable {
    let scale: CGFloat
    let blur: CGFloat
    let bounds: Rect
}
