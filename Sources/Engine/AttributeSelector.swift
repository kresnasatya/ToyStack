// MARK: - AttributeSelector
struct AttributeSelector: CSSSelector {
    let attribute: String
    let value: String?
    let priority: Int = 10
    var hasSelectors: [HasSelector] { [] }
    var bucketKey: SelectorBucketKey { .universal }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element,
            let actual = element.attributes[attribute]
        else { return false }
        guard let value = value else { return true }
        return actual == value
    }
}
