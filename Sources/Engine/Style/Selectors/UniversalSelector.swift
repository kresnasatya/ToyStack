// MARK: - UniversalSelector
struct UniversalSelector: CSSSelector {
    let priority: Int = 0
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .universal }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        return snapshot.node(index).content.tag != nil
    }
}
