import CoreGraphics

struct PaintKey: Equatable, Sendable {
    let width: CGFloat
    let height: CGFloat
    let epoch: UInt
    /// Style revision of the block's own DOM node. A paint-only change on
    /// another element (for example a link hover) does not move this.
    let revision: UInt64

    init(width: CGFloat, height: CGFloat, epoch: UInt, revision: UInt64 = 0) {
        self.width = width
        self.height = height
        self.epoch = epoch
        self.revision = revision
    }
}
