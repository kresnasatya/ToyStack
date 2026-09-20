struct FrameTiming {
    let totalFrames: Int
    let easing: Easing
}

extension FrameTiming {
    static func parse(_ value: String) -> [String: FrameTiming] {
        var properties: [String: FrameTiming] = [:]
        guard !value.isEmpty else { return properties }
        for item in splitOutsiteParentheses(value, separator: ",") {
            let normalized: String = item.split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let tokens: [String] = splitOutsiteParentheses(normalized, separator: " ").filter({
                !$0.isEmpty
            })
            guard tokens.count >= 2 else { continue }
            let property: String = tokens[0]
            let durationStr: String = tokens[1]
            guard durationStr.hasSuffix("s"), let seconds = Double(durationStr.dropLast())
            else { continue }
            let totalFrames: Int = Int(seconds / secondsPerFrame)
            let easing: Easing = tokens.count >= 3 ? Easing.parse(tokens[2]) : .ease
            properties[property] = FrameTiming(totalFrames: totalFrames, easing: easing)
        }
        return properties
    }
}
