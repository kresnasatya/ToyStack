import CoreGraphics

// MARK: - DrawLine
public struct DrawLine: DisplayCommand {
    public let rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: VisualEffect? = nil

    public init(
        from: CGPoint,
        to: CGPoint,
        color: String,
        thickness: CGFloat
    ) {
        self.rect = Rect(left: from.x, top: from.y, right: to.x, bottom: to.y)
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.strokeSegment(
            from: CGPoint(x: rect.left, y: rect.top - scroll),
            to: CGPoint(x: rect.right, y: rect.bottom - scroll),
            color: BrowserColor(cssName: color),
            lineWidth: thickness
        )
    }
}
