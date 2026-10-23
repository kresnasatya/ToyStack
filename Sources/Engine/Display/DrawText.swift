import CoreGraphics

// MARK: - DrawText
public struct DrawText: DisplayCommand {
    public var rect: Rect
    public let text: String
    public let font: BrowserFont
    public let color: String
    public var parentEffect: BrowserVisualEffect? = nil

    public init(
        rect: Rect, text: String, font: BrowserFont, color: String
    ) {
        self.rect = rect
        self.text = text
        self.font = font
        self.color = color
    }

    public init(
        at point: Point, text: String, font: BrowserFont, color: String
    ) {
        self.init(
            rect: Rect(
                left: point.x,
                top: point.y,
                right: point.x + font.measure(text),
                bottom: point.y + font.linespace
            ),
            text: text,
            font: font,
            color: color
        )
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.drawText(text, font: font, color: BrowserColor(cssName: color), at: Point(x: rect.left, y: rect.top - scroll))
    }

    public func shifted(dx: CGFloat, dy: CGFloat) -> any DisplayCommand {
        var copy: DrawText = self
        copy.rect = rect.translated(dx: dx, dy: dy)
        return copy
    }
}
