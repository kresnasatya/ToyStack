enum AnimatedValue {
    case number(Double)
    case length(Double)
    case color(RGBColor)

    var length: Double? {
        guard case .length(let value) = self else { return nil }
        return value
    }

    init?(css: String, property: String) {
        switch property {
        case "opacity":
            guard let v = Double(css) else { return nil }
            self = .number(v)
        case "width", "height":
            guard css.hasSuffix("px"), let v = Double(css.dropLast(2)) else { return nil }
            self = .length(v)
        case "background-color":
            guard let c = cssColorToRGB(css) else { return nil }
            self = .color(c)
        default:
            return nil
        }
    }
}
