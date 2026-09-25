import CoreGraphics

// MARK: - DrawText
public struct DrawText: DisplayCommand {
    public let rect: Rect
    public let text: String
    public let font: BrowserFont
    public let color: String
    public var parentEffect: BrowserVisualEffect? = nil

    public init(
        at point: CGPoint, text: String, font: BrowserFont, color: String
    ) {
        self.rect = Rect(
            left: point.x,
            top: point.y,
            right: point.x + font.measure(text),
            bottom: point.y + font.linespace
        )
        self.text = text
        self.font = font
        self.color = color
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.drawText(text, font: font.ctFont, color: BrowserColor(cssName: color), at: CGPoint(x: rect.left, y: rect.top - scroll))
    }
}
