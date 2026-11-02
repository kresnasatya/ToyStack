struct RasterScene {
    let displayList: [DisplayOp]
    let compositedUpdates: [NodeID: EffectUpdate]
    let previousLayers: [CompositedLayer]
}
