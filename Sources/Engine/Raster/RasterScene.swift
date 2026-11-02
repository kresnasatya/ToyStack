struct RasterScene {
    let displayList: [DisplayOp]
    let compositedUpdates: [ObjectIdentifier: BrowserVisualEffect]
    let previousLayers: [CompositedLayer]
}
