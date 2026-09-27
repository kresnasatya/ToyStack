public struct PresentedFrame {
    public let content: RenderedContent
    public let viewport: PresentedViewport

    public init(content: RenderedContent, viewport: PresentedViewport) {
        self.content = content
        self.viewport = viewport
    }
}
