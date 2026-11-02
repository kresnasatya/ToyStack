struct RasterScene {
    let displayList: [DisplayOp]
    let compositedUpdates: [NodeKey: EffectUpdate]
    let previousLayers: [CompositedLayer]
}
