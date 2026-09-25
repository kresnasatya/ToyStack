// MARK: - Cascade Priority
func cascadePriority(_ rule: (String?, any CSSSelector, [String: String])) -> Int {
    rule.1.priority
}

func isDescendantRule(_ selector: any CSSSelector) -> Bool {
    if selector is DescendantSelector { return true }
    if let important = selector as? ImportantSelector {
        return isDescendantRule(important.base)
    }
    if let pseudoclass = selector as? PseudoclassSelector {
        return isDescendantRule(pseudoclass.base)
    }
    return false
}

func precomputeHas(node: any DOMNode, rules: [(String?, any CSSSelector, [String: String])]) {
    let allNodes: [any DOMNode] = treeToList(node)

    for n in allNodes { n.satisfiedHas = [] }

    let allHasSelectors: [HasSelector] = rules.flatMap({ $0.1.hasSelectors })
    guard !allHasSelectors.isEmpty else { return }

    for n in allNodes.reversed() {
        for hs in allHasSelectors {
            for child in n.children {
                if hs.inner.matches(child) || child.satisfiedHas.contains(hs.id) {
                    n.satisfiedHas.insert(hs.id)
                    break
                }
            }
        }
    }
}
