import CoreGraphics

struct LinePaintKey: Equatable {
    let x: CGFloat
    let y: CGFloat
    let epoch: UInt
    let generation: UInt

    init(x: CGFloat, y: CGFloat, epoch: UInt, generation: UInt) {
        self.x = x
        self.y = y
        self.epoch = epoch
        self.generation = generation
    }
}
