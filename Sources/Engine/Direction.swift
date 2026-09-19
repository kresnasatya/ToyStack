enum Direction: String {
    case ltr
    case rtl

    init(cssValue: String?) {
        self = Direction(rawValue: cssValue ?? "") ?? .ltr
    }
}
