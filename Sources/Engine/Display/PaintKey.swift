import CoreGraphics

struct PaintKey: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    let epoch: UInt
    let revision: UInt64

    init(width: CGFloat, height: CGFloat, epoch: UInt, revision: UInt64 = 0) {
        self.width = width
        self.height = height
        self.epoch = epoch
        self.revision = revision
    }
}
