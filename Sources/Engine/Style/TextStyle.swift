import CoreGraphics

// MARK: - TextStyle

struct TextStyle: Equatable {
    var color: BrowserColor
    var font: Font
    var whiteSpace: WhiteSpaceMode
    var direction: TextDirection

    static let initial: TextStyle = TextStyle(
        color: BrowserColor(red: 0, green: 0, blue: 0),
        font: Font(family: "serif", size: 16, style: .normal, weight: .normal),
        whiteSpace: .normal,
        direction: .ltr
    )
}

// MARK: - Font

extension TextStyle {
    struct Font: Equatable {
        var family: String
        var size: CGFloat
        var style: TextStyle.Style
        var weight: TextStyle.Weight
    }

    enum Style: Equatable {
        case normal
        case italic
        case oblique

        init(css: String?) {
            switch css {
            case "italic": self = .italic
            case "oblique": self = .oblique
            default: self = .normal
            }
        }

        var browserFontStyle: String {
            switch self {
            case .normal: return "roman"
            case .italic: return "italic"
            case .oblique: return "oblique"
            }
        }
    }

    enum Weight: Equatable {
        case normal
        case bold
        case number(Int)

        init(css: String?) {
            switch css {
            case "bold": self = .bold
            case "normal": self = .normal
            case let value?:
                if let number = Int(value) {
                    self = .number(number)
                } else {
                    self = .normal
                }
            case nil: self = .normal
            }
        }

        var cssValue: String {
            switch self {
            case .normal: return "normal"
            case .bold: return "bold"
            case .number(let value): return String(value)
            }
        }
    }
}
