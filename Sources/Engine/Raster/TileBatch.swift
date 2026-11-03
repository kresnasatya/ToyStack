import CoreGraphics

struct TileBatch: Sendable {
    let strips: [TileStrip]
    let tabHeight: CGFloat
    let deferred: Bool
}
