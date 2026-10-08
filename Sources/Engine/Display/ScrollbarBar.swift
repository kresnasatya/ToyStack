import CoreGraphics

// MARK: - ScrollbarBar
public struct ScrollbarBar: DisplayCommand {
    public let rect: Rect
    public let color: String
    public let radius: CGFloat
    public var parentEffect: BrowserVisualEffect? = nil

    public init(rect: Rect, color: String, radius: CGFloat = 0) {
        self.rect = rect
        self.color = color
        self.radius = radius
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        let target: Rect = Rect(
            left: rect.left,
            top: rect.top - scroll,
            right: rect.right,
            bottom: rect.bottom - scroll
        )
        if radius > 0 {
            renderer.fillRRect(target, radius: radius, color: BrowserColor(cssName: color))
        } else {
            renderer.fillRect(target, color: BrowserColor(cssName: color))
        }

    }
}
