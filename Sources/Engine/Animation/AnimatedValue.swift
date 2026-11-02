import CoreGraphics

enum AnimatedValue: Equatable {
    case number(Double)
    case length(CGFloat)
    case color(BrowserColor)
    case transform(CGPoint)

    init?(css: String, property: StyleProperty) {
        switch property {
        case .opacity:
            guard let v = Double(css) else { return nil }
            self = .number(v)
        case .width, .height:
            guard css.hasSuffix("px"), let v = Double(css.dropLast(2)) else { return nil }
            self = .length(CGFloat(v))
        case .backgroundColor:
            guard let c = BrowserColor.parse(css) else { return nil }
            self = .color(c)
        default:
            return nil
        }
    }
}
