import CoreGraphics

public protocol Renderer {
    func saveState()
    func restoreState()
    func translateBy(x: CGFloat, y: CGFloat)
    func clip(to rect: Rect)
    func fillRect(_ rect: Rect, color: BrowserColor)
    func fillRRect(_ rect: Rect, radius: CGFloat, color: BrowserColor)
    func strokeSegment(from: Point, to: Point, color: BrowserColor, lineWidth: CGFloat)
    func strokeRect(_ rect: Rect, color: BrowserColor, lineWidth: CGFloat)
    func drawText(_ text: String, font: BrowserFont, color: BrowserColor, at point: Point)
    func drawImage(_ image: CGImage, in rect: Rect)
    func drawImage(_ image: CGImage, in rect: Rect, rendering: ImageRendering)
    func drawLayer(_ options: LayerOptions, content: (any Renderer) -> Void)
}

extension Renderer {
    public func drawImage(_ image: CGImage, in rect: Rect, rendering: ImageRendering) {
        drawImage(image, in: rect)
    }
}
