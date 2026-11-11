import Foundation

struct FramePaintState: Sendable {
    var ops: [DisplayOp]
    var revision: UInt
    var epoch: UInt
    var isNeeded: Bool

    init() {
        self.ops = []
        self.revision = 0
        self.epoch = 0
        self.isNeeded = false
    }
}
