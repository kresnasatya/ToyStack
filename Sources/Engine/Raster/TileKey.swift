struct TileKey: Hashable, Sendable {
    let layer: LayerID
    let index: TileIndex
    let contentHash: Int
    let scale: Int
}
