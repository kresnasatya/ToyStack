import CoreGraphics

// MARK: - Length

enum Length: Equatable {
    case px(CGFloat)
    case percent(CGFloat)

    init?(css: String?) {
        guard let css else { return nil }
        let trimmed: String = css.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%"), let value = Double(trimmed.dropLast()) {
            self = .percent(CGFloat(value))
        } else if trimmed.hasSuffix("px"), let value = Double(trimmed.dropLast(2)) {
            self = .px(CGFloat(value))
        } else {
            return nil
        }
    }

    func resolved(available: CGFloat, zoom: CGFloat) -> CGFloat {
        switch self {
        case .px(let value):
            return value * zoom
        case .percent(let value):
            return available * value / 100
        }
    }
}
