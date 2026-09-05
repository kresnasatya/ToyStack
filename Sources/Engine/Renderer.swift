import CoreGraphics
import CoreText

public struct EngineColor {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(cssName: String) {
        let name = cssName.lowercased().trimmingCharacters(in: .whitespaces)
        if name == "transparent" {
            self = EngineColor(red: 0, green: 0, blue: 0, alpha: 0)
            return
        }
        if let rgb = cssColorToRGB(name) {
            self = EngineColor(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255)
        } else {
            self = EngineColor(red: 0, green: 0, blue: 0)
        }
    }
}

public enum EngineBlendMode: String {
    case normal
    case multiply
    case difference
    case destinationIn
}

public struct LayerOptions {
    public var opacity: Double?
    public var blendMode: EngineBlendMode?
    public var blur: CGFloat?

    public init(opacity: Double? = nil, blendMode: EngineBlendMode? = nil, blur: CGFloat? = nil) {
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
    func fillRect(_ rect: CGRect, color: EngineColor)
    func fillRRect(_ rect: CGRect, radius: CGFloat, color: EngineColor)
    func strokeSegment(from: CGPoint, to: CGPoint, color: EngineColor, lineWidth: CGFloat)
    func strokeRect(_ rect: CGRect, color: EngineColor, lineWidth: CGFloat)
    func drawText(_ text: String, font: CTFont, color: EngineColor, at point: CGPoint)
    func drawImage(_ image: CGImage, in rect: CGRect)
    func drawLayer(_ options: LayerOptions, content: (any Renderer) -> Void)
}
