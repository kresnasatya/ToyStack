import Foundation

func splitOutsiteParentheses(_ value: String, separator: Character) -> [String] {
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
func parseTransform(_ value: String) -> CGPoint? {
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

func parseBlur(_ value: String) -> CGFloat {
    guard value.hasPrefix("blur("), value.hasSuffix(")") else { return 0 }
    let inner: Substring.SubSequence = value.dropFirst(5).dropLast()
    let digits: Substring.SubSequence = inner.hasSuffix("px") ? inner.dropLast(2) : inner
    return CGFloat(Double(digits) ?? 0)
}
