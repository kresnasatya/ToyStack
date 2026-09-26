// MARK: - PseudoclassSelector
struct PseudoclassSelector: CSSSelector {
    let pseudoclass: String
    let base: any CSSSelector
    var priority: Int { base.priority }
    var hasSelectors: [HasSelector] { base.hasSelectors }
    var key: SelectorKey { base.key }

    func matches(_ node: any DOMNode) -> Bool {
        guard base.matches(node) else { return false }
        switch pseudoclass {
        case "focus": return node.isFocused
        case "focus-visible": return node.isFocusVisible
        default: return false
        }
    }
}
