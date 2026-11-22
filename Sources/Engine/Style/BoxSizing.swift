import CoreGraphics

// MARK: - BoxSizing

enum BoxSizing: Equatable {
    case contentBox
    case borderBox

    init(css: String?) {
        switch css?.lowercased() {
        case "border-box": self = .borderBox
        default: self = .contentBox
        }
    }

    // CSS Sizing 3 §3.3: border-box assigns the specified size to the border box, so it
    // includes padding and border and the content box gets what is left, floored at zero.
    func contentSize(specified: CGFloat, paddingAndBorder: CGFloat) -> CGFloat {
        switch self {
        case .contentBox: return specified
        case .borderBox: return max(0, specified - paddingAndBorder)
        }
    }
}
