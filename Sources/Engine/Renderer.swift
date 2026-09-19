import CoreGraphics
import CoreText

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

public protocol Renderer {
    func saveState()
    func restoreState()
    func translateBy(x: CGFloat, y: CGFloat)
    func clip(to rect: CGRect)
    func fillRect(_ rect: CGRect, color: BrowserColor)
    func fillRRect(_ rect: CGRect, radius: CGFloat, color: BrowserColor)
    func strokeSegment(from: CGPoint, to: CGPoint, color: BrowserColor, lineWidth: CGFloat)
    func strokeRect(_ rect: CGRect, color: BrowserColor, lineWidth: CGFloat)
    func drawText(_ text: String, font: CTFont, color: BrowserColor, at point: CGPoint)
    func drawImage(_ image: CGImage, in rect: CGRect)
    func drawLayer(_ options: LayerOptions, content: (any Renderer) -> Void)
}
