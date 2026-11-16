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

    // CSS Sizing 3 §3.3: under border-box the specified size includes padding
    // and border, so the content box gets what is left, floored at zero.
    func contentSize(specified: CGFloat, paddingAndBorder: CGFloat) -> CGFloat {
        switch self {
        case .contentBox: return specified
        case .borderBox: return max(0, specified - paddingAndBorder)
        }
    }
}
