// MARK: - BackgroundSizeSpec

enum BackgroundSizeSpec: Equatable {
    case auto
    case cover
    case contain
    case lengths(Length?, Length?)

    init?(css: String?) {
        guard let css else { return nil }
        let tokens: [String] = css
            .split(whereSeparator: { $0 == " " }).map(String.init)
        guard let first = tokens.first?.lowercased() else { return nil }
        switch first {
        case "cover":
            self = .cover
            return
        case "contain":
            self = .contain
            return
        default:
            break
        }
        let second: String? = tokens.count > 1 ? tokens[1].lowercased() : nil
        if first == "auto", second == nil || second == "auto" {
            self = .auto
            return
        }
        let width: Length? = first == "auto" ? nil : Length(css: first)
        let height: Length? = second == nil || second == "auto" ? nil : Length(css: second)
        self = .lengths(width, height)
    }
}
