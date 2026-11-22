import CoreGraphics

struct InlineLinePlan: Equatable {
    let lines: [[Int]]
    var fits: Range<CGFloat>?
}
