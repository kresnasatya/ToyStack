import CoreGraphics

struct LinePaintVersion: Equatable, Sendable {
    let generation: UInt
    let style: UInt64
}

struct LinePaintKey: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let epoch: UInt
    let version: LinePaintVersion

    init(x: CGFloat, y: CGFloat, epoch: UInt, version: LinePaintVersion) {
        self.x = x
        self.y = y
        self.epoch = epoch
        self.version = version
    }
}
