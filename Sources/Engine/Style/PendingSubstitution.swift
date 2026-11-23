// MARK: - PendingSubstitution

struct PendingSubstitution {
    let shorthand: String
    let value: String

    private static let marker: Character = "\u{0}"

    init(shorthand: String, value: String) {
        self.shorthand = shorthand
        self.value = value
    }

    init?(cascaded: String) {
        guard cascaded.first == PendingSubstitution.marker else { return nil }
        let parts: [Substring] = cascaded.dropFirst().split(
            separator: PendingSubstitution.marker,
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else { return nil }
        self.shorthand = String(parts[0])
        self.value = String(parts[1])
    }

    var cascaded: String {
        return "\(PendingSubstitution.marker)\(shorthand)\(PendingSubstitution.marker)\(value)"
    }
}
