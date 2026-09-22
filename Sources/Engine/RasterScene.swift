struct RasterScene {
    let displayList: [any PaintItem]
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayers: [CompositedLayer]
}
