import CoreGraphics

public struct LayerEffect {
    public let key: NodeKey?
    public let opacity: Double
    public let translation: CGPoint
    public let blendMode: BrowserBlendMode?
    public let clipRect: Rect?

    public init(key: NodeKey? = nil, opacity: Double = 1, translation: CGPoint = .zero, blendMode: BrowserBlendMode? = nil, clipRect: Rect? = nil) {
        self.key = key
        self.opacity = opacity
        self.translation = translation
        self.blendMode = blendMode
        self.clipRect = clipRect
    }
}
