// MARK: - IDSelector
struct IDSelector: CSSSelector {
    let id: String
    let priority: Int = 100
    var hasSelectors: [HasSelector] { [] }
    var bucketKey: SelectorBucketKey { .id(id) }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element else { return false }
        return element.attributes["id"] == id
    }
}
