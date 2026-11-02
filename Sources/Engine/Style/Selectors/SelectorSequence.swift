// MARK: - SelectorSequence
struct SelectorSequence: CSSSelector {
    let selectors: [any CSSSelector]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }
    var key: SelectorKey {
        selectors.map({ $0.key }).max(by: { $0.rank < $1.rank }) ?? .universal
    }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        selectors.allSatisfy({ $0.matches(node) })
    }
}
