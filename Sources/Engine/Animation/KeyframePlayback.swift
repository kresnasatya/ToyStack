// MARK: - CSS animation shorthand
struct KeyframePlayback {
    let name: String
    let totalFrames: Int
    let infinite: Bool
    let alternate: Bool
}

extension KeyframePlayback {
    static func parse(_ value: String) -> KeyframePlayback? {
        let tokens: [String] = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var name: String?
        var totalFrames: Int?
        var infinite: Bool = false
        var alternate: Bool = false

        for token in tokens {
            if token.hasSuffix("s"), let seconds = Double(token.dropLast()) {
                totalFrames = Int(seconds / secondsPerFrame)
            } else if token == "infinite" {
                infinite = true
            } else if token == "alternate" {
                alternate = true
            } else {
                name = token
            }
        }

        guard let n = name, let tf = totalFrames else { return nil }
        return KeyframePlayback(name: n, totalFrames: tf, infinite: infinite, alternate: alternate)
    }

}
