import CoreGraphics

public struct PresentedFrame {
    public let revision: PresentedRevision
    public let frameID: Int
    public let content: RenderedContent
    public let viewport: PresentedViewport
    /// Viewport size at which this content was laid out.
    public let layoutSize: CGSize

    public init(
        revision: PresentedRevision = PresentedRevision(content: 0, sequence: 0),
        frameID: Int = 0,
        content: RenderedContent,
        viewport: PresentedViewport,
        layoutSize: CGSize = .zero
    ) {
        self.revision = revision
        self.frameID = frameID
        self.content = content
        self.viewport = viewport
        self.layoutSize = layoutSize
    }
}
