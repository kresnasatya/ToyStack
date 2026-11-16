public enum CursorKind: Equatable, Sendable {
    case auto
    case `default`
    case pointer

    init?(css: String) {
        switch css.lowercased() {
        case "auto", "initial": self = .auto
        case "default": self = .default
        case "pointer": self = .pointer
        default: return nil
        }
    }

    // css-ui-4 §5.1.1: `cursor` is inherited with initial value `auto`. The
    // nearest element in the chain that declares a supported value wins, which
    // also makes `inherit`, `unset`, and unsupported values defer to the parent.
    @MainActor
    static func inherited(along chain: [NodeID], in dom: DOMTree) -> CursorKind {
        for id in chain {
            if let raw: String = dom.style(of: id).unknownValue("cursor"),
                let kind: CursorKind = CursorKind(css: raw)
            {
                return kind
            }
        }
        return .auto
    }
}
