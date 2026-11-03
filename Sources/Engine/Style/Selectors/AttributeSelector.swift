// MARK: - AttributeSelector
struct AttributeSelector: CSSSelector {
    let attribute: String
    let value: String?
    let priority: Int = 10
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .universal }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        guard let actual = snapshot.node(index).content.attributes[attribute] else { return false }
        guard let value = value else { return true }
        return actual == value
    }
}
