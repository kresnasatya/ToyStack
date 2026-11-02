struct FrameRender {
    var layers: [CompositedLayer] = []
    var drawList: [DisplayOp] = []
    var content: RenderedContent = RenderedContent()
    var signature: FrameSignature?
}
