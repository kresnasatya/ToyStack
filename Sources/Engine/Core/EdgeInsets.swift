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

    subscript(side: BoxSide) -> CGFloat {
        switch side {
        case .top: return top
        case .right: return right
        case .bottom: return bottom
        case .left: return left
        }
    }

    func scaled(by factor: CGFloat) -> EdgeInsets {
        return EdgeInsets(
            top: top * factor,
            right: right * factor,
            bottom: bottom * factor,
            left: left * factor
        )
    }

    static func + (lhs: EdgeInsets, rhs: EdgeInsets) -> EdgeInsets {
        return EdgeInsets(
            top: lhs.top + rhs.top,
            right: lhs.right + rhs.right,
            bottom: lhs.bottom + rhs.bottom,
            left: lhs.left + rhs.left
        )
    }
}
