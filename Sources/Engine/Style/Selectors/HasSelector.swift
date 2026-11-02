// MARK: - HasSelector
struct HasSelector: CSSSelector {
    nonisolated(unsafe) private static var counter: Int = 0
    let id: Int
    let inner: any CSSSelector
    var priority: Int { inner.priority }
    var hasSelectors: [HasSelector] { [self] }
    var key: SelectorKey { .universal }

    init(inner: any CSSSelector) {
        self.id = HasSelector.counter
        HasSelector.counter += 1
        self.inner = inner
    }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        node.satisfiedHas.contains(id)
    }
}
