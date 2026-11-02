// MARK: - TagSelector
struct TagSelector: CSSSelector {
    let tag: String
    let priority: Int = 1
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .tag(tag) }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        guard let element = node.element else {
            return false
        }
        return element.tag == tag
    }
}
