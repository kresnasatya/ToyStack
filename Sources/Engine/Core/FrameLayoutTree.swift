import Foundation

struct FrameLayoutTree {
    var box: LayoutBox?
    var isDirty: Bool
    var forced: Bool

    init() {
        self.box = nil
        self.isDirty = true
        self.forced = true
    }
}
