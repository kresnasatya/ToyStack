import CoreGraphics

// MARK: - FloatRegistry

/// Floats move text and blocks that are not their layout inputs, so the
/// document keeps track of them and of the blocks that read them.
struct FloatRegistry {
    /// The margin box of every placed float.
    var boxes: [LayoutID: FloatBox] = [:]
    /// Floats, clearing blocks, and blocks moved beside floats; they re-place
    /// themselves when a float before them changes.
    var positioned: Set<LayoutID> = []
    /// Inline blocks whose lines are shortened or that place floats of their
    /// own, with the floats they were laid out against; they re-check those
    /// floats when a float before them changes.
    var wrapped: [LayoutID: [FloatBox]] = [:]
    /// Margin-box origins for floats inside inline content, chosen by the
    /// block whose lines they sit in while it breaks those lines.
    var anchors: [LayoutID: CGPoint] = [:]

    mutating func forget(_ removed: Set<LayoutID>) {
        guard !removed.isEmpty else { return }
        boxes = boxes.filter({ !removed.contains($0.key) })
        positioned.subtract(removed)
        wrapped = wrapped.filter({ !removed.contains($0.key) })
        anchors = anchors.filter({ !removed.contains($0.key) })
    }
}

// MARK: - FloatBox

struct FloatBox: Equatable {
    let side: LayoutStyle.FloatSide
    let rect: Rect
}
