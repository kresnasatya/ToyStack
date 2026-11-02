struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [DisplayOp]?
    let content: RenderedContent
    let needsMoreTiles: Bool
}
