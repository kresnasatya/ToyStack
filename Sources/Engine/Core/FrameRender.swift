struct FrameRender {
    var layers: [CompositedLayer] = []
    var drawList: [any DisplayItem] = []
    var content: RenderedContent = RenderedContent()
    var signature: FrameSignature?
}
