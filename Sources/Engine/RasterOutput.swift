struct RasterOutput: @unchecked Sendable {
    let compositedLayers: [CompositedLayer]?
    let drawList: [Any]?
    let content: RenderedContent
    let structureSignature: Int
}
