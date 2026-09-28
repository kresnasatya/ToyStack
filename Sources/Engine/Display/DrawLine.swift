import CoreGraphics

// MARK: - DrawLine
public struct DrawLine: DisplayCommand {
    public let rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: BrowserVisualEffect? = nil

    public init(
        from: Point,
        to: Point,
        color: String,
        thickness: CGFloat
    ) {
        self.rect = Rect(left: from.x, top: from.y, right: to.x, bottom: to.y)
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.strokeSegment(
            from: Point(x: rect.left, y: rect.top - scroll),
            to: Point(x: rect.right, y: rect.bottom - scroll),
            color: BrowserColor(cssName: color),
            lineWidth: thickness
        )
    }
}
