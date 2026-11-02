// MARK: - ImportantSelector
struct ImportantSelector: CSSSelector {
    let base: any CSSSelector
    var priority: Int { base.priority + 10_000 }
    var hasSelectors: [HasSelector] { base.hasSelectors }
    var key: SelectorKey { base.key }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        base.matches(node)
    }
}
