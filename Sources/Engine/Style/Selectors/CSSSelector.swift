// MARK: - CSSSelector
protocol CSSSelector: Sendable {
    var priority: Int { get }
    var hasSelectors: [HasSelector] { get }
    var bucketKey: SelectorBucketKey { get }
    func matches(_ node: any DOMNode) -> Bool
}
