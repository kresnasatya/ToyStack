struct RasterCommit: @unchecked Sendable {
    let inputs: RasterInput
    let layers: [CompositedLayer]
    let infos: [LayerEffectInfo]
    let usesSublayers: Bool
}
