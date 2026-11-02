// MARK: - PseudoclassSelector
struct PseudoclassSelector: CSSSelector {
    let pseudoclass: String
    let base: any CSSSelector
    var priority: Int { base.priority }
    var hasSelectors: [HasSelector] { base.hasSelectors }
    var key: SelectorKey { base.key }

    @MainActor
    func matches(_ node: DOMRef) -> Bool {
        guard base.matches(node) else { return false }
        switch pseudoclass {
        case "focus": return node.isFocused
        case "focus-visible": return node.isFocusVisible
        case "hover": return node.isHovered
        default: return false
        }
    }
}
