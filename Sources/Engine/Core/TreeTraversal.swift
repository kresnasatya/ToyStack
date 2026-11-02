import Foundation

// MARK: - Tree Utilities

@MainActor
func treeToList(_ node: DOMRef) -> [DOMRef] {
    var result: [DOMRef] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}

@MainActor
func treeToList(_ ref: LayoutRef, into list: inout [LayoutRef]) {
    list.append(ref)
    for child in ref.children { treeToList(child, into: &list) }
}

@MainActor
func treeToList(_ ref: LayoutRef) -> [LayoutRef] {
    var list: [LayoutRef] = []
    treeToList(ref, into: &list)
    return list
}

@MainActor
func treeToList(_ node: AccessibilityNode) -> [AccessibilityNode] {
    var result: [AccessibilityNode] = [node]
    for child in node.children {
        result.append(contentsOf: treeToList(child))
    }
    return result
}
