import CoreGraphics

struct TileStrip: Sendable {
    let layerIndex: Int
    let bounds: Rect
    let content: TileStripContent
    let tiles: [TileKey]

    init(layerIndex: Int, bounds: Rect, content: TileStripContent, tiles: [TileKey]) {
        self.layerIndex = layerIndex
        self.bounds = bounds
        self.content = content
        self.tiles = tiles
    }
}

extension TileStrip {
    static func sliceRect(for key: TileKey, in bounds: Rect, grid: TileGrid) -> CGRect {
        let pixels: CGFloat = grid.devicePixels
        let stripLeft: CGFloat = (bounds.left * grid.scale.effective).rounded()
        let stripTop: CGFloat = (bounds.top * grid.scale.effective).rounded()
        return CGRect(
            x: CGFloat(key.index.col) * pixels - stripLeft,
            y: CGFloat(key.index.row) * pixels - stripTop,
            width: pixels,
            height: pixels
        )
    }
}

// MARK: - TileStripContent

struct TileStripContent: Sendable {
    let items: [DisplayOp]
    let clips: [ClipShape]

    init(items: [DisplayOp], clips: [ClipShape]) {
        self.items = items
        self.clips = clips
    }
}
