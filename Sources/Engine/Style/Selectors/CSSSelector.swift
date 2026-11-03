// MARK: - CSSSelector
protocol CSSSelector: Sendable {
    var priority: Int { get }
    var hasSelectors: [HasSelector] { get }
    var key: SelectorKey { get }
    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool
}
