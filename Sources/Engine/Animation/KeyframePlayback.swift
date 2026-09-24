// MARK: - KeyframePlayback
struct KeyframePlayback {
    let name: String
    let timing: FrameTiming
    let infinite: Bool
    let alternate: Bool
}

extension KeyframePlayback {
    static func parse(_ value: String) -> KeyframePlayback? {
        let normalized: String = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let tokens: [String] = CSSValueParser.splitOutsiteParentheses(normalized, separator: " ").filter({ !$0.isEmpty })
        guard !tokens.isEmpty else { return nil }

        var name: String?
        var totalFrames: Int?
        var easing: Easing = .ease
        var infinite: Bool = false
        var alternate: Bool = false

        for token in tokens {
            if token.hasSuffix("s"), let seconds = Double(token.dropLast()) {
                totalFrames = Int(seconds / secondsPerFrame)
            } else if token == "infinite" {
                infinite = true
            } else if token == "alternate" {
                alternate = true
            } else if let parsed = Easing.parseIfValid(token) {
                easing = parsed
            } else {
                name = token
            }
        }

        guard let n = name, let tf = totalFrames else { return nil }
        return KeyframePlayback(
            name: n,
            timing: FrameTiming(totalFrames: tf, easing: easing),
            infinite: infinite,
            alternate: alternate
        )
    }

}
