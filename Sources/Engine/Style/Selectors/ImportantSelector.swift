// MARK: - ImportantSelector
struct ImportantSelector: CSSSelector {
    let base: any CSSSelector
    var priority: Int { base.priority + 10_000 }
    var hasSelectors: [HasSelector] { base.hasSelectors }
    var bucketKey: SelectorBucketKey { base.bucketKey }

    func matches(_ node: any DOMNode) -> Bool {
        base.matches(node)
    }
}
