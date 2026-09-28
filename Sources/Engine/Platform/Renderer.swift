import CoreGraphics
import CoreText

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
