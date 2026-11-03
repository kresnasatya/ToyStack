struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [RasterLayer]?
    let drawList: [DisplayOp]?
    let content: RenderedContent
    let needsMoreTiles: Bool
}
