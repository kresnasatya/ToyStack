struct RasterScene {
    let displayList: [Any]
    let compositedUpdates: [ObjectIdentifier: VisualEffect]
    let previousLayers: [CompositedLayer]
}
