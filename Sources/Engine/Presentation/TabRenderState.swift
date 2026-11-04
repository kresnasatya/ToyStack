struct TabRenderState {
    var composite: TabCompositeState = TabCompositeState()
    var drawList: [DisplayOp] = []
    var content: RenderedContent = RenderedContent()
    var signature: FrameSignature?
}
