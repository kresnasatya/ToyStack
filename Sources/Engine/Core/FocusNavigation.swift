func isFocusable(_ node: DOMNode) -> Bool {
    guard let el = node as? Element else { return false }
    return ["input", "button", "a"].contains(el.tag) || el.attributes["tabindex"] != nil
}

func getTabIndex(_ node: DOMNode) -> Int {
    guard let el = node as? Element,
        let val = el.attributes["tabindex"],
        let idx = Int(val)
    else { return 9_999_999 }
    return idx
}
