// MARK: - Tree Utilities
func treeToList(_ node: any DOMNode) -> [any DOMNode] {
    var result: [any DOMNode] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

func treeToList(_ obj: any LayoutObject) -> [any LayoutObject] {
    var result: [any LayoutObject] = [obj]
    for child in obj.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

func treeToList(_ item: any DisplayItem, into list: inout [any DisplayItem]) {
    list.append(item)
    if let ve = item as? VisualEffect {
        for child in ve.children {
            treeToList(child, into: &list)
        }
    }
}

func treeToList(_ node: AccessibilityNode) -> [AccessibilityNode] {
    var result: [AccessibilityNode] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}
