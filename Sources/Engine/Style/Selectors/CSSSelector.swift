// MARK: - CSSSelector
protocol CSSSelector: Sendable {
    var priority: Int { get }
    var hasSelectors: [HasSelector] { get }
    var key: SelectorKey { get }
    @MainActor func matches(_ node: DOMRef) -> Bool
}
