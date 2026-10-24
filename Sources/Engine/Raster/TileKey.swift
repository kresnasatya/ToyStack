struct TileKey: Hashable {
    let layer: LayerID
    let index: TileIndex
    let contentHash: Int
    // `displayScale * pageZoom`, in thousandths.
    let scale: Int
}
