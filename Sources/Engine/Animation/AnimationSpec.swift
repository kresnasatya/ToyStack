// MARK: - CSS animation shorthand
struct AnimationSpec {
    let name: String
    let numFrames: Int
    let infinite: Bool
    let alternate: Bool
}

func parseAnimationShorthand(_ value: String) -> AnimationSpec? {
    let tokens: [String] = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !tokens.isEmpty else { return nil }

    var name: String?
    var numFrames: Int?
    var infinite: Bool = false
    var alternate: Bool = false

    for token in tokens {
        if token.hasSuffix("s"), let seconds = Double(token.dropLast()) {
            numFrames = Int(seconds / REFRESH_RATE_SEC)
        } else if token == "infinite" {
            infinite = true
        } else if token == "alternate" {
            alternate = true
        } else {
            name = token
        }
    }

    guard let n = name, let nf = numFrames else { return nil }
    return AnimationSpec(name: n, numFrames: nf, infinite: infinite, alternate: alternate)
}
