import CoreGraphics

struct TileScale: Hashable, Sendable {
    let thousandths: Int

    init(_ scale: CGFloat) {
        thousandths = Int((scale * 1000).rounded())
    }
}
