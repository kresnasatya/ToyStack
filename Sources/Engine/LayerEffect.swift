import CoreGraphics

public struct LayerEffect {
    public let key: ObjectIdentifier?
    public let opacity: Double
    public let translation: CGPoint
    public let blendMode: BrowserBlendMode?

    public init(key: ObjectIdentifier? = nil, opacity: Double = 1, translation: CGPoint = .zero, blendMode: BrowserBlendMode? = nil) {
        self.key = key
        self.opacity = opacity
        self.translation = translation
        self.blendMode = blendMode
    }
}
