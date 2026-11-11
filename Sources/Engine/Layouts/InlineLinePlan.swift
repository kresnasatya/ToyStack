import CoreGraphics

/// Where a block's inline items break into lines, and the widths that
/// produce exactly those breaks.
///
/// The breaks come from a greedy pass: an item that wraps breaks the line when
/// `cursorX + width > available`. As long as every such comparison has the
/// same answer, every `cursorX` is the same too, so the plan holds for any
/// width that is at least the end of every item that stayed on its line and
/// less than the end of every item that broke.
struct InlineLinePlan: Equatable {
    let lines: [[Int]]
    /// Widths that give these breaks, or nil once the items have changed size
    /// (a font refresh keeps the old breaks only so placement can reuse lines).
    var fits: Range<CGFloat>?
}
