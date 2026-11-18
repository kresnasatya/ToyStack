// MARK: - TextUnit

/// How much text a press takes and a drag grows by: a click works between
/// characters, a double click in whole words, and a third click or more in
/// whole paragraphs.
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
