struct TabRenderState {
    var layers: [RasterLayer] = []
    var drawList: [DisplayOp] = []
    var content: RenderedContent = RenderedContent()
    var signature: FrameSignature?
}
