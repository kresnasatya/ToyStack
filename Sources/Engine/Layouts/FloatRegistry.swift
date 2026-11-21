import CoreGraphics

// MARK: - FloatRegistry

/// Floats move text and blocks that are not their layout inputs, so the
/// document keeps track of them and of the blocks that read them.
struct FloatRegistry {
    /// The margin box of every placed float.
    var boxes: [LayoutID: FloatBox] = [:]
    /// Floats and blocks with `clear`; they re-place themselves on every
    /// layout pass.
    var positioned: Set<LayoutID> = []
    /// Inline blocks whose lines are shortened, with the floats they were
    /// broken against; they re-check those floats on every layout pass.
    var wrapped: [LayoutID: [FloatBox]] = [:]
}

// MARK: - FloatBox

struct FloatBox: Equatable {
    let side: LayoutStyle.FloatSide
    let rect: Rect
}
