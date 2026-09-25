// MARK: - SelectorSequence
struct SelectorSequence: CSSSelector {
    let selectors: [any CSSSelector]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }
    var bucketKey: SelectorBucketKey {
        selectors.map({ $0.bucketKey }).max(by: { $0.rank < $1.rank }) ?? .universal
    }

    func matches(_ node: any DOMNode) -> Bool {
        selectors.allSatisfy({ $0.matches(node) })
    }
}
