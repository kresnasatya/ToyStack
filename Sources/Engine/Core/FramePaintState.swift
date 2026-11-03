import Foundation

/// The display list produced by paint and the revision that identifies it.
struct FramePaintState {
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
