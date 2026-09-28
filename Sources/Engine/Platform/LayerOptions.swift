import CoreGraphics

public struct LayerOptions {
    public var opacity: Double?
    public var blendMode: BrowserBlendMode?
    public var blur: CGFloat?

    public init(opacity: Double? = nil, blendMode: BrowserBlendMode? = nil, blur: CGFloat? = nil) {
        self.opacity = opacity
        self.blendMode = blendMode
        self.blur = blur
    }
}
