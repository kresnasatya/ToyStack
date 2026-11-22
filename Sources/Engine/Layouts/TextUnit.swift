// MARK: - TextUnit

enum TextUnit {
    case character
    case word
    case paragraph

    init(clickCount: Int) {
        switch clickCount {
        case ...1: self = .character
        case 2: self = .word
        default: self = .paragraph
        }
    }
}
