enum TextDirection: String {
    case ltr
    case rtl

    init(cssValue: String?) {
        self = TextDirection(rawValue: cssValue ?? "") ?? .ltr
    }
}
