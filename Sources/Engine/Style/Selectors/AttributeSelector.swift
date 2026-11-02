// MARK: - AttributeSelector
struct AttributeSelector: CSSSelector {
    let attribute: String
    let value: String?
    let priority: Int = 10
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .universal }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        guard let element = node.element,
            let actual = element.attributes[attribute]
        else { return false }
        guard let value = value else { return true }
        return actual == value
    }
}
