import CoreGraphics

// MARK: - DrawRect
public struct DrawRect: DisplayCommand {
    public var rect: Rect
    public let color: String
    public var parentEffect: BrowserVisualEffect? = nil

    public init(rect: Rect, color: String) {
        self.rect = rect
        self.color = color
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.fillRect(
            Rect(left: rect.left, top: rect.top - scroll, right: rect.right, bottom: rect.bottom - scroll),
            color: BrowserColor(cssName: color)
        )
    }

    public func shifted(dx: CGFloat, dy: CGFloat) -> any DisplayCommand {
        var copy: DrawRect = self
        copy.rect = rect.translated(dx: dx, dy: dy)
        return copy
    }
}
