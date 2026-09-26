import Foundation

enum WhiteSpaceMode: Equatable {
    case normal
    case nowrap
    case pre
    case preWrap
    case preLine

    init(cssValue: String?) {
        switch cssValue ?? "normal" {
            case "pre": self = .pre
            case "nowrap": self = .nowrap
            case "pre-wrap": self = .preWrap
            case "pre-line": self = .preLine
            default: self = .normal
        }
    }

    var keepSpaces: Bool {
        self == .pre || self == .preWrap
    }

    var keepsNewlines: Bool {
        self == .pre || self == .preWrap || self == .preLine
    }

    var wraps: Bool {
        self == .normal || self == .preWrap || self == .preLine
    }
}
