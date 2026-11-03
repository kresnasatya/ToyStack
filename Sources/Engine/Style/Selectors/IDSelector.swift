// MARK: - IDSelector
struct IDSelector: CSSSelector {
    let id: String
    let priority: Int = 100
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .id(id) }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        return snapshot.node(index).content.attributes["id"] == id
    }
}
