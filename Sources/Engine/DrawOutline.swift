import CoreGraphics

// MARK: - DrawOutline
public struct DrawOutline: DisplayCommand {
    public let rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: VisualEffect? = nil

    public init(rect: Rect, color: String, thickness: CGFloat) {
        self.rect = rect
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        let r: CGRect = CGRect(
            x: rect.left, y: rect.top - scroll, width: rect.right - rect.left,
            height: rect.bottom - rect.top)
        renderer.strokeRect(r, color: BrowserColor(cssName: color), lineWidth: thickness)
    }
}
