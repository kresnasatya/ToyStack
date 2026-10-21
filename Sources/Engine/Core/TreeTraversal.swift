// MARK: - Tree Utilities
func treeToList(_ node: any DOMNode) -> [any DOMNode] {
    var result: [any DOMNode] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

@MainActor
func treeToList(_ obj: any LayoutObject, into list: inout [any LayoutObject]) {
    list.append(obj)
    for child in obj.children { treeToList(child, into: &list) }
}

@MainActor
func treeToList(_ obj: any LayoutObject) -> [any LayoutObject] {
    var list: [any LayoutObject] = []
    treeToList(obj, into: &list)
    return list
}

func treeToList(_ item: any DisplayItem, into list: inout [any DisplayItem]) {
    list.append(item)
    if let ve = item as? BrowserVisualEffect {
        for child in ve.children {
            treeToList(child, into: &list)
        }
    }
}

@MainActor
func treeToList(_ node: AccessibilityNode) -> [AccessibilityNode] {
    var result: [AccessibilityNode] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}
