public struct PresentedFrame {
    public let revision: Int
    public let frameID: Int
    public let content: RenderedContent
    public let viewport: PresentedViewport

    public init(revision: Int = 0, frameID: Int = 0, content: RenderedContent, viewport: PresentedViewport) {
        self.revision = revision
        self.frameID = frameID
        self.content = content
        self.viewport = viewport
    }
}
