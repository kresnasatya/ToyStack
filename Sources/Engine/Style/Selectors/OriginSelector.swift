// MARK: - CascadeOrigin
enum CascadeOrigin {
    case userAgent
    case author
}

// MARK: - OriginSelector
struct OriginSelector: CSSSelector {
    let base: any CSSSelector
    let origin: CascadeOrigin
    let isImportant: Bool
    // CSS Cascade 4 §6.1: origin and importance rank before specificity. In
    // ascending order: normal user agent, normal author, important author,
    // important user agent. Each band is wider than any selector's specificity.
    var priority: Int {
        switch (origin, isImportant) {
        case (.userAgent, false): return base.priority - 1_000_000
        case (.author, false): return base.priority
        case (.author, true): return base.priority + 1_000_000
        case (.userAgent, true): return base.priority + 2_000_000
        }
    }
    var hasSelectors: [HasSelector] { base.hasSelectors }
    var key: SelectorKey { base.key }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        return base.matches(snapshot, index)
    }
}
