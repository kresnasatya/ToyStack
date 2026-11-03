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

@MainActor
func precomputeHas(node: DOMRef, rules: [(String?, any CSSSelector, [String: String])]) {
    let allHasSelectors: [HasSelector] = rules.flatMap({ $0.1.hasSelectors })
    guard !allHasSelectors.isEmpty else { return }

    var snapshot: StyleSnapshot = StyleSnapshotBuilder.build(root: node)
    fillHas(&snapshot, selectors: allHasSelectors)
    writeBack(&snapshot, into: node)
}

func fillHas(_ snapshot: inout StyleSnapshot, selectors: [HasSelector]) {
    for index in snapshot.nodes.indices {
        snapshot.nodes[index]?.state.satisfiedHas = []
    }
    var order: [Int] = []
    snapshot.preorder(from: snapshot.root, into: &order)
    for index in order.reversed() {
        for selector in selectors {
            for child in snapshot.children(of: index) {
                let matched: Bool = selector.inner.matches(snapshot, child)
                    || snapshot.node(child).state.satisfiedHas.contains(selector.id)
                if matched {
                    snapshot.nodes[index]?.state.satisfiedHas.insert(selector.id)
                    break
                }
            }
        }
    }
}

@MainActor
private func writeBack(_ snapshot: inout StyleSnapshot, into root: DOMRef) {
    for node in treeToList(root) {
        guard let index: Int = snapshot.index(of: node.id) else { continue }
        node.satisfiedHas = snapshot.node(index).state.satisfiedHas
    }
}
