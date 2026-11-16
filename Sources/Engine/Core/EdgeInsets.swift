import CoreGraphics

// MARK: - EdgeInsets

struct EdgeInsets: Equatable {
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    let left: CGFloat

    static let zero: EdgeInsets = EdgeInsets(top: 0, right: 0, bottom: 0, left: 0)

    var horizontal: CGFloat { left + right }
    var vertical: CGFloat { top + bottom }

    func scaled(by factor: CGFloat) -> EdgeInsets {
        return EdgeInsets(
            top: top * factor,
            right: right * factor,
            bottom: bottom * factor,
            left: left * factor
        )
    }
}
