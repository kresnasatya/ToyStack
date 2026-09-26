// MARK: - UniversalSelector
struct UniversalSelector: CSSSelector {
    let priority: Int = 0
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .universal }

    func matches(_ node: any DOMNode) -> Bool {
        node is Element
    }
}
