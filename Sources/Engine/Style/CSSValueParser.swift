import Foundation

enum CSSValueParser {

    private static let translatePattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"translate\((-?[0-9.]+)px,\s*(-?[0-9.]+)px\)"#
    )

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
        guard value.contains("translate("), let regex = translatePattern,
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

    static func backgroundImageURL(_ value: String) -> String? {
        guard value.lowercased().hasPrefix("url("), value.hasSuffix(")") else { return nil }
        var inner: String = String(value.dropFirst(4).dropLast())
            .trimmingCharacters(in: .whitespaces)
        if inner.count >= 2 {
            if (inner.hasPrefix("\"") && inner.hasSuffix("\"")) || (inner.hasPrefix("'") && inner.hasSuffix("'")) {
                inner = String(inner.dropFirst().dropLast())
            }
        }
        return inner.isEmpty ? nil : inner
    }
}
