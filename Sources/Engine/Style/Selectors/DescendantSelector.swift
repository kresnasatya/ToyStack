// MARK: - DescendantSelector
struct DescendantSelector: CSSSelector {
    let selectors: [any CSSSelector]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }
    var key: SelectorKey { selectors.last?.key ?? .universal }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        guard selectors.last!.matches(node) else { return false }

        var j: Int = selectors.count - 2
        var current: DOMRef? = node.parent
        while let p = current {
            if j < 0 { return true }
            if selectors[j].matches(p) { j -= 1 }
            current = p.parent
        }
        return j < 0
    }
}
