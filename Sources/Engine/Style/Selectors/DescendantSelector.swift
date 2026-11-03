// MARK: - DescendantSelector
struct DescendantSelector: CSSSelector {
    let selectors: [any CSSSelector]
    var priority: Int { selectors.reduce(0, { $0 + $1.priority }) }
    var hasSelectors: [HasSelector] { selectors.flatMap { $0.hasSelectors } }
    var key: SelectorKey { selectors.last?.key ?? .universal }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        guard selectors.last!.matches(snapshot, index) else { return false }

        var j: Int = selectors.count - 2
        var current: Int? = snapshot.parent(of: index)
        while let p = current {
            if j < 0 { return true }
            if selectors[j].matches(snapshot, p) { j -= 1 }
            current = snapshot.parent(of: p)
        }
        return j < 0
    }
}
