struct RasterScene {
    let displayList: [any DisplayItem]
    let compositedUpdates: [ObjectIdentifier: BrowserVisualEffect]
    let previousLayers: [CompositedLayer]
}
