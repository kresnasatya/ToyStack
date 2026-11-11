@MainActor
func isFocusable(_ node: DOMRef) -> Bool {
    guard let el = node.element else { return false }
    return ["input", "button", "a"].contains(el.tag)
        || el.attributes["tabindex"] != nil
        || el.attributes["contenteditable"] != nil
}

@MainActor
func explicitTabIndex(_ node: DOMRef) -> Int? {
    guard let el = node.element,
        let val = el.attributes["tabindex"],
        let idx = Int(val)
    else { return nil }
    return idx
}

@MainActor
func isTabFocusable(_ node: DOMRef) -> Bool {
    guard isFocusable(node) else { return false }
    return (explicitTabIndex(node) ?? 0) >= 0
}

struct FocusTarget {
    let frame: FrameID
    let element: NodeID
}

@MainActor
func focusOrder(of root: Frame) -> [FocusTarget] {
    let tab: BrowserTab? = root.tab
    return inDocumentOrder(of: root)
        .enumerated()
        .sorted { tabOrderKey($0.element, tab: tab, offset: $0.offset)  < tabOrderKey($1.element, tab: tab, offset: $1.offset) }
        .map(\.element)
}

@MainActor
private func tabOrderKey(_ target: FocusTarget, tab: BrowserTab?, offset: Int) -> TabOrderKey {
    guard let frame: Frame = tab?.frame(target.frame) else { return (.documentOrder, 0, offset) }
    let node: DOMRef = frame.dom.ref(target.element)
    if let idx = explicitTabIndex(node), idx > 0 {
        return (.positiveTabIndex, idx, offset)
    }
    return (.documentOrder, 0, offset)
}

@MainActor
private func inDocumentOrder(of frame: Frame) -> [FocusTarget] {
    guard frame.document != nil else { return [] }
    var targets: [FocusTarget] = []
    for node in treeToList(frame.nodes) {
        if isTabFocusable(node) {
            targets.append(FocusTarget(frame: frame.links.id, element: node.id))
        }
        if let element = node.element, element.tag == "iframe", let child = element.frame {
            targets.append(contentsOf: inDocumentOrder(of: child))
        }
    }
    return targets
}

private typealias TabOrderKey = (group: TabOrderGroup, tabIndex: Int, documentPosition: Int)

private enum TabOrderGroup: Comparable {
    case positiveTabIndex
    case documentOrder
}
