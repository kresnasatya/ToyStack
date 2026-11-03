// MARK: - ClassSelector
struct ClassSelector: CSSSelector {
    let cls: String
    let priority: Int = 10
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .className(cls) }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        let classes: [String] =
            snapshot.node(index).content.attributes["class"]?
            .split(separator: " ").map(String.init) ?? []
        return classes.contains(cls)
    }
}
