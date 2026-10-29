import Foundation

@MainActor
enum StyleInvalidation {

    static func markNodeAndAncestors(_ node: any DOMNode) {
        node.style.markAll()
        markAncestorStyles(node)
    }

    static func markSubtreeAndAncestors(_ node: any DOMNode) {
        markSubtree(node)
        markAncestorStyles(node)
    }

    static func markNode(_ node: any DOMNode) {
        node.style.markAll()
        setAncestorFlags(node)
    }

    static func markDocument(_ root: any DOMNode) {
        for node in treeToList(root) {
            node.style.markAll()
        }
    }

    private static func markSubtree(_ node: any DOMNode) {
        for target in treeToList(node) {
            target.style.markAll()
        }
    }

    private static func markAncestorStyles(_ node: any DOMNode) {
        var current: (any DOMNode)? = node.parent
        while let ancestor = current {
            ancestor.style.markAll()
            ancestor.style.markDirtyDescendants()
            current = ancestor.parent
        }
    }

    private static func setAncestorFlags(_ node: any DOMNode) {
        var current: (any DOMNode)? = node.parent
        while let ancestor = current, !ancestor.style.hasDirtyDescendant {
            ancestor.style.markDirtyDescendants()
            current = ancestor.parent
        }
    }
}
