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

    private static func shorthandCornerRadii(_ css: String?) -> CornerRadii? {
        guard let css else { return nil }
        let halves: [Substring] = css.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let horizontal = radiusLengths(halves[0]) else { return nil }
        let vertical: [RadiusLength]
        if halves.count == 2 {
            guard let parsed = radiusLengths(halves[1]) else { return nil }
            vertical = parsed
        } else {
            vertical = horizontal
        }
        guard let h = CornerRadii.expanded(horizontal),
            let v = CornerRadii.expanded(vertical)
        else { return nil }
        let corners: [CornerRadius] = zip(h, v).map {
            CornerRadius(horizontal: $0, vertical: $1)
        }
        let radii: CornerRadii = CornerRadii(corners: corners)
        return radii.isZero ? nil : radii
    }

    static func cornerRadii(_ style: [String: String]) -> CornerRadii? {
        let shorthand: CornerRadii = shorthandCornerRadii(style["border-radius"]) ?? .zero
        let corners: [CornerRadius] = [
            cornerRadius(style["border-top-left-radius"]) ?? shorthand.topLeft,
            cornerRadius(style["border-top-right-radius"]) ?? shorthand.topRight,
            cornerRadius(style["border-bottom-right-radius"]) ?? shorthand.bottomRight,
            cornerRadius(style["border-bottom-left-radius"]) ?? shorthand.bottomLeft,
        ]
        let radii: CornerRadii = CornerRadii(corners: corners)
        return radii.isZero ? nil : radii
    }

    private static func cornerRadius(_ css: String?) -> CornerRadius? {
        guard let css, let values = radiusLengths(Substring(css)) else { return nil }
        switch values.count {
        case 1:
            return CornerRadius(horizontal: values[0], vertical: values[0])
        case 2:
            return CornerRadius(horizontal: values[0], vertical: values[1])
        default:
            return nil
        }
    }

    private static func radiusLengths(_ css: Substring) -> [RadiusLength]? {
        let tokens: [Substring] = css.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return nil }
        var values: [RadiusLength] = []
        values.reserveCapacity(tokens.count)
        for token in tokens {
            guard let value = radiusLength(token) else { return nil }
            values.append(value)
        }
        return values
    }

    private static func radiusLength(_ token: Substring) -> RadiusLength? {
        if token.hasSuffix("%"), let value = Double(token.dropLast()), value >= 0 {
            return .percent(CGFloat(value))
        }
        if token.hasSuffix("px"), let value = Double(token.dropLast(2)), value >= 0 {
            return .px(CGFloat(value))
        }
        return nil
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
