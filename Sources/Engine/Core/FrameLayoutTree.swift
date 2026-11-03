import Foundation

/// The current layout tree and whether the next render must lay it out again.
struct FrameLayoutTree {
    var box: LayoutBox?
    var isDirty: Bool

    init() {
        self.box = nil
        self.isDirty = true
    }
}
