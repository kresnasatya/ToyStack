import Foundation

/// The current layout tree and whether the next render must lay it out again.
struct FrameLayoutTree {
    var value: LayoutTree?
    var isDirty: Bool

    init() {
        self.value = nil
        self.isDirty = true
    }
}
