struct RasterComposition: @unchecked Sendable {
    let inputs: RasterInput
    let layers: [RasterLayer]
    let effectStrategies: [LayerEffectStrategy]
    let usesSublayers: Bool
}
