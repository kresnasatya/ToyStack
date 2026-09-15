import CoreGraphics

struct TileStrip: @unchecked Sendable {
    let layer: CompositedLayer
    let bounds: Rect
    let items: [PaintCommand]
    let tiles: [TileKey]

    init(layer: CompositedLayer, bounds: Rect, items: [PaintCommand], tiles: [TileKey]) {
        self.layer = layer
        self.bounds = bounds
        self.items = items
        self.tiles = tiles
    }
}

extension TileStrip {
    static func sliceRect(for key: TileKey, in bounds: Rect, scale: CGFloat) -> CGRect {
        let t = CompositedLayer.tileSize
        return CGRect(
            x: (CGFloat(key.index.col) * t - bounds.left) * scale,
            y: (CGFloat(key.index.row) * t - bounds.top) * scale,
            width: t * scale,
            height: t * scale
        )
    }
}
