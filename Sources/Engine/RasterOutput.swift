struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [any PaintItem]?
    let content: RenderedContent
    let needsMoreTiles: Bool
}
