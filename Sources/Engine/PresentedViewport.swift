import CoreGraphics

public struct PresentedViewport {
    public let contentOffset: CGFloat
    public let displayScale: CGFloat
    public let canvasColor: CGColor
    public let scrollbar: (frame: CGRect, color: CGColor)?

    public init(
        contentOffset: CGFloat,
        displayScale: CGFloat,
        canvasColor: CGColor,
        scrollbar: (frame: CGRect, color: CGColor)?
    ) {
        self.contentOffset = contentOffset
        self.displayScale = displayScale
        self.canvasColor = canvasColor
        self.scrollbar = scrollbar
    }
}
