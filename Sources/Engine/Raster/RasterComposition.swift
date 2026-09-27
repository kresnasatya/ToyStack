struct RasterComposition: @unchecked Sendable {
    let inputs: RasterInput
    let layers: [CompositedLayer]
    let effectStrategies: [LayerEffectStrategy]
    let usesSublayers: Bool
}
