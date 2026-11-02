// MARK: - UniversalSelector
struct UniversalSelector: CSSSelector {
    let priority: Int = 0
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .universal }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        node.element != nil
    }
}
