import CoreGraphics

// MARK: - RadiusLength

enum RadiusLength: Hashable {
    case px(CGFloat)
    case percent(CGFloat)

    func resolved(against size: CGFloat) -> CGFloat {
        switch self {
        case .px(let value): return value
        case .percent(let value): return size * value / 100
        }
    }

    var isZero: Bool {
        switch self {
        case .px(let value), .percent(let value): return value == 0
        }
    }
}
