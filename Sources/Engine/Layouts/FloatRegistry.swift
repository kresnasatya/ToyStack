import CoreGraphics

// MARK: - FloatRegistry

/// Floats move text and blocks that are not their layout inputs, so the
/// document keeps track of them and of the blocks that read them.
struct FloatRegistry {
    /// The margin box of every placed float.
    var boxes: [LayoutID: FloatBox] = [:]
    /// Floats, clearing blocks, and blocks moved beside floats; they re-place
    /// themselves on every layout pass.
    var positioned: Set<LayoutID> = []
    /// Inline blocks whose lines are shortened or that place floats of their
    /// own, with the floats they were laid out against; they re-check those
    /// floats on every layout pass.
    var wrapped: [LayoutID: [FloatBox]] = [:]
    /// Margin-box origins for floats inside inline content, chosen by the
    /// block whose lines they sit in while it breaks those lines.
    var anchors: [LayoutID: CGPoint] = [:]
}

// MARK: - FloatBox

struct FloatBox: Equatable {
    let side: LayoutStyle.FloatSide
    let rect: Rect
}
