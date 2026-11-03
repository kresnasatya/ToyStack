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
func treeToList(_ tree: LayoutTree, _ root: LayoutID) -> [LayoutID] {
    var list: [LayoutID] = []
    var stack: [LayoutID] = [root]
    while let id = stack.popLast() {
        list.append(id)
        stack.append(contentsOf: tree.childrenIDs(of: id).reversed())
    }
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
