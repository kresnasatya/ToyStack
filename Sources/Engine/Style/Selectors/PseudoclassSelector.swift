// MARK: - PseudoclassSelector
struct PseudoclassSelector: CSSSelector {
    let pseudoclass: String
    let base: any CSSSelector
    var priority: Int { base.priority }
    var hasSelectors: [HasSelector] { base.hasSelectors }
    var key: SelectorKey { base.key }

    func matches(_ snapshot: StyleSnapshot, _ index: Int) -> Bool {
        guard base.matches(snapshot, index) else { return false }
        let state: StyleState = snapshot.node(index).state
        switch pseudoclass {
        case "focus": return state.isFocused
        case "focus-visible": return state.isFocusVisible
        case "hover": return state.isHovered
        default: return false
        }
    }
}
