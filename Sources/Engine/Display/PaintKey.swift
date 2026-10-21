import CoreGraphics

struct PaintKey: Equatable {
    let rect: Rect
    let epoch: UInt
    let generation: UInt

    init(rect: Rect, epoch: UInt, generation: UInt) {
        self.rect = rect
        self.epoch = epoch
        self.generation = generation
    }
}
