import CoreGraphics

public struct PresentedFrame {
    public let revision: PresentedRevision
    public let frameID: Int
    public let content: RenderedContent
    public let viewport: PresentedViewport

    /// The size the composited content occupies in view pixels.
    public var displayedLayoutSize: CGSize {
        let layoutSize: CGSize = content.source.layoutSize
        return CGSize(
            width: layoutSize.width * viewport.scale.page,
            height: layoutSize.height * viewport.scale.page
        )
    }

    public init(
        revision: PresentedRevision = PresentedRevision(content: 0, sequence: 0),
        frameID: Int = 0,
        content: RenderedContent,
        viewport: PresentedViewport
    ) {
        self.revision = revision
        self.frameID = frameID
        self.content = content
        self.viewport = viewport
    }
}
