import CoreGraphics

struct TileStrip: Sendable {
    let layerIndex: Int
    let bounds: Rect
    let items: [DisplayOp]
    let tiles: [TileKey]

    init(layerIndex: Int, bounds: Rect, items: [DisplayOp], tiles: [TileKey]) {
        self.layerIndex = layerIndex
        self.bounds = bounds
        self.items = items
        self.tiles = tiles
    }
}

extension TileStrip {
    static func sliceRect(for key: TileKey, in bounds: Rect, scale: CGFloat) -> CGRect {
        let t: CGFloat = RasterLayer.tileSize
        return CGRect(
            x: (CGFloat(key.index.col) * t - bounds.left) * scale,
            y: (CGFloat(key.index.row) * t - bounds.top) * scale,
            width: t * scale,
            height: t * scale
        )
    }
}
