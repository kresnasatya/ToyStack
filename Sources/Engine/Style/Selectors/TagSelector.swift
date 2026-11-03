// MARK: - TagSelector
struct TagSelector: CSSSelector {
    let tag: String
    let priority: Int = 1
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .tag(tag) }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        return snapshot.node(index).content.tag == tag
    }
}
