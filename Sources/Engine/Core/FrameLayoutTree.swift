import Foundation

/// The current layout tree and whether the next render must lay it out again.
struct FrameLayoutTree {
    var box: LayoutBox?
    var isDirty: Bool
    /// A caller asked for a pass without marking a field, so the pass may not
    /// be skipped even when the tree reports nothing dirty.
    var forced: Bool

    init() {
        self.box = nil
        self.isDirty = true
        self.forced = true
    }
}
