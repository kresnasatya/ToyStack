struct RasterScene {
    let displayList: [any DisplayItem]
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayers: [CompositedLayer]
}
