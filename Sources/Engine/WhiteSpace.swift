import Foundation

enum WhiteSpace: Equatable {
    case normal
    case nowrap
    case pre
    case preWrap
    case preLine

    static func mode(of node: any DOMNode) -> WhiteSpace {
        switch node.style["white-space"] ?? "normal" {
            case "pre": return .pre
            case "nowrap": return .nowrap
            case "pre-wrap": return .preWrap
            case "pre-line": return .preLine
            default: return .normal
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
