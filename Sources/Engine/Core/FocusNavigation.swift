func isFocusable(_ node: DOMNode) -> Bool {
    guard let el = node as? Element else { return false }
    return ["input", "button", "a"].contains(el.tag) || el.attributes["tabindex"] != nil
}

func explicitTabIndex(_ node: DOMNode) -> Int? {
    guard let el = node as? Element,
        let val = el.attributes["tabindex"],
        let idx = Int(val)
    else { return nil }
    return idx
}

func isTabFocusable(_ node: DOMNode) -> Bool {
    guard isFocusable(node) else { return false }
    return (explicitTabIndex(node) ?? 0) >= 0
}

struct FocusTarget {
    let frame: Frame
    let element: Element
}

@MainActor
func focusOder(of root: Frame) -> [FocusTarget] {
    return inDocumentOrder(of: root)
        .enumerated()
        .sorted { tabOrderKey($0.element, offset: $0.offset)  < tabOrderKey($1.element, offset: $1.offset) }
        .map(\.element)
}

// Group 0: an explicit positive tabindex, ordered by value.
// Group 1: tabindex="0" or no tabindex, in document order.
private func tabOrderKey(_ target: FocusTarget, offset: Int) -> (Int, Int, Int) {
    if let idx = explicitTabIndex(target.element), idx > 0 {
        return (0, idx, offset)
    }
    return (1, 0, offset)
}

@MainActor
private func inDocumentOrder(of frame: Frame) -> [FocusTarget] {
    guard frame.document != nil else { return [] }
    var targets: [FocusTarget] = []
    for node in treeToList(frame.nodes) {
        guard let element = node as? Element else { continue }
        if isTabFocusable(element) {
            targets.append(FocusTarget(frame: frame, element: element))
        }
        if element.tag == "iframe", let child = element.frame {
            targets.append(contentsOf: inDocumentOrder(of: child))
        }
    }
    return targets
}
