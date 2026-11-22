// MARK: - IsSelector
// Selectors 4 §4.2 and §4.4: :is() and :where() match when any selector in their list
// matches. §15: :is() counts as its most specific argument, :where() counts as nothing.
struct IsSelector: CSSSelector {
    let alternatives: [any CSSSelector]
    let keepsSpecificity: Bool
    var priority: Int { keepsSpecificity ? alternatives.map({ $0.priority }).max() ?? 0 : 0 }
    var hasSelectors: [HasSelector] { alternatives.flatMap { $0.hasSelectors } }
    var key: SelectorKey { alternatives.count == 1 ? alternatives[0].key : .universal }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        return alternatives.contains(where: { $0.matches(snapshot, index) })
    }
}
