import CoreGraphics

struct PaintKey: Equatable {
    let width: CGFloat
    let height: CGFloat
    let epoch: UInt

    init(width: CGFloat, height: CGFloat, epoch: UInt) {
        self.width = width
        self.height = height
        self.epoch = epoch
    }
}
