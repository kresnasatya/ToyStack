import Foundation

enum CSSValueParser {
    static func splitOutsiteParentheses(_ value: String, separator: Character) -> [String] {
        var parts: [String] = []
        var depth: Int = 0
        var current: String = ""
        for ch in value {
            if ch == "(" {
                depth += 1
                current.append(ch)
            } else if ch == ")" {
                depth -= 1
                current.append(ch)
            } else if ch == separator && depth == 0 {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    // MARK: - CSS transform parsing
    static func transform(_ value: String) -> CGPoint? {
        let pattern: String = #"translate\((-?[0-9.]+)px,\s*(-?[0-9.]+)px\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
            let xRange = Range(match.range(at: 1), in: value),
            let yRange = Range(match.range(at: 2), in: value),
            let x = Double(value[xRange]),
            let y = Double(value[yRange])
        else { return nil }
        return CGPoint(x: x, y: y)
    }

    static func blur(_ value: String) -> CGFloat {
        guard value.hasPrefix("blur("), value.hasSuffix(")") else { return 0 }
        let inner: Substring.SubSequence = value.dropFirst(5).dropLast()
        let digits: Substring.SubSequence = inner.hasSuffix("px") ? inner.dropLast(2) : inner
        return CGFloat(Double(digits) ?? 0)
    }

    static func outlineWidth(_ token: String) -> CGFloat? {
        switch token {
            case "thin": return 1
            case "medium": return 3
            case "thick": return 5
            default:
                guard token.hasSuffix("px"), let value = Double(token.dropLast(2)) else { return nil }
                return CGFloat(value)
        }
    }

}
