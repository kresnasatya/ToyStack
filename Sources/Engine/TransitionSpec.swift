let REFRESH_RATE_SEC: Double = 1.0 / 60.0

func parseTransition(_ value: String) -> [String: TransitionSpec] {
    var properties: [String: TransitionSpec] = [:]
    guard !value.isEmpty else { return properties }
    for item in splitTopLevel(value, separator: ",") {
        let normalized: String = item.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let tokens: [String] = splitTopLevel(normalized, separator: " ").filter({
            !$0.isEmpty
        })
        guard tokens.count >= 2 else { continue }
        let property: String = tokens[0]
        let durationStr: String = tokens[1]
        guard durationStr.hasSuffix("s"), let seconds = Double(durationStr.dropLast())
        else { continue }
        let numFrames: Int = Int(seconds / REFRESH_RATE_SEC)
        let easing: EasingFunction = tokens.count >= 3 ? EasingFunction.parse(tokens[2]) : .ease
        properties[property] = TransitionSpec(numFrames: numFrames, easing: easing)
    }
    return properties
}

func splitTopLevel(_ value: String, separator: Character) -> [String] {
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
