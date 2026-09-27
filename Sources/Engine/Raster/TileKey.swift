struct TileKey: Hashable {
    let origin: TileLayerOrigin
    let index: TileIndex
    let contentHash: Int
    let scale: Int
}
