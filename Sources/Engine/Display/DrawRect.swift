import CoreGraphics

// MARK: - DrawRect
public struct DrawRect: DisplayCommand {
    public let rect: Rect
    public let color: String
    public var parentEffect: BrowserVisualEffect? = nil

    public init(rect: Rect, color: String) {
        self.rect = rect
        self.color = color
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        let r: CGRect = CGRect(
            x: rect.left,
            y: rect.top - scroll,
            width: rect.right - rect.left,
            height: rect.bottom - rect.top
        )
        renderer.fillRect(r, color: BrowserColor(cssName: color))
    }
}
