// MARK: - ClassSelector
struct ClassSelector: CSSSelector {
    let cls: String
    let priority: Int = 10
    var hasSelectors: [HasSelector] { [] }
    var key: SelectorKey { .className(cls) }

    func matches(_ node: any DOMNode) -> Bool {
        guard let element = node as? Element else { return false }
        let classes: [String] = element.attributes["class"]?.split(separator: " ").map(String.init) ?? []
        return classes.contains(cls)
    }
}
