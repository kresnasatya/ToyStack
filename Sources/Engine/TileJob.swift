import CoreGraphics

struct TileJob {
    let index: TileIndex
    let key: TileKey
    let inside: [PaintCommand]
    let origin: CGPoint

    init(index: TileIndex, key: TileKey, inside: [PaintCommand], origin: CGPoint) {
        self.index = index
        self.key = key
        self.inside = inside
        self.origin = origin
    }
}
