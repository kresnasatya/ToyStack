public struct PresentedFrame {
    public let frameID: Int
    public let content: RenderedContent
    public let viewport: PresentedViewport

    public init(frameID: Int = 0, content: RenderedContent, viewport: PresentedViewport) {
        self.frameID = frameID
        self.content = content
        self.viewport = viewport
    }
}
