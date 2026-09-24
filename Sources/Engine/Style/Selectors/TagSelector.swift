// MARK: - TagSelector
struct TagSelector: CSSSelector {
    let tag: String
    let priority: Int = 1
    var hasSelectors: [HasSelector] { [] }
    var bucketKey: SelectorBucketKey { .tag(tag) }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element else {
            return false
        }
        return element.tag == tag
    }
}
