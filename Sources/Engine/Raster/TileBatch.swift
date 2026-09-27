import CoreGraphics

struct TileBatch: @unchecked Sendable {
    let strips: [TileStrip]
    let tabHeight: CGFloat
    let deferred: Bool
}
