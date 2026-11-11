import CoreGraphics

public struct LayerEffectImage: Sendable {
    var image: CGImage?
    var key: EffectImageKey?

    init() {
        self.image = nil
        self.key = nil
    }
}

// MARK: - EffectImageKey

public struct EffectImageKey: Equatable, Sendable {
    let scale: CGFloat
    let blur: CGFloat
    let bounds: Rect
}
