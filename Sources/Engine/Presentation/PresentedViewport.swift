import CoreGraphics

public struct PresentedViewport {
    public let contentOffset: ContentOffset
    public let scale: ContentScale
    public let canvasColor: CGColor
    public let scrollbar: (frame: CGRect, color: CGColor)?

    public init(
        contentOffset: ContentOffset,
        scale: ContentScale,
        canvasColor: CGColor,
        scrollbar: (frame: CGRect, color: CGColor)?
    ) {
        self.contentOffset = contentOffset
        self.scale = scale
        self.canvasColor = canvasColor
        self.scrollbar = scrollbar
    }
}
