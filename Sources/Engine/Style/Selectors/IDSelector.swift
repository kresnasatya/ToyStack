// MARK: - IDSelector
struct IDSelector: CSSSelector {
    let id: String
    let priority: Int = 100
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .id(id) }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        guard let element = node.element else { return false }
        return element.attributes["id"] == id
    }
}
