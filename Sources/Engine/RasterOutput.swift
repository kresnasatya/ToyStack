struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [any DisplayItem]?
    let content: RenderedContent
    let needsMoreTiles: Bool
}
