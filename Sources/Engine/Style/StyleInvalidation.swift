import Foundation

@MainActor
enum StyleInvalidation {

    static func markNodeAndAncestors(_ node: DOMRef) {
        node.style.markAll()
        markAncestorStyles(node)
    }

    static func markSubtreeAndAncestors(_ node: DOMRef) {
        markSubtree(node)
        markAncestorStyles(node)
    }

    static func markNode(_ node: DOMRef) {
        node.style.markAll()
        setAncestorFlags(node)
    }

    static func markDocument(_ root: DOMRef) {
        for node in treeToList(root) {
            node.style.markAll()
        }
    }

    private static func markSubtree(_ node: DOMRef) {
        for target in treeToList(node) {
            profiler.count("style.invalidate.subtree.nodes")
            target.style.markAll()
        }
    }

    private static func markAncestorStyles(_ node: DOMRef) {
        var current: DOMRef? = node.parent
        while let ancestor = current {
            ancestor.style.markAll()
            ancestor.style.markDirtyDescendants()
            current = ancestor.parent
        }
    }

    private static func setAncestorFlags(_ node: DOMRef) {
        var current: DOMRef? = node.parent
        while let ancestor = current, !ancestor.style.hasDirtyDescendant {
            ancestor.style.markDirtyDescendants()
            current = ancestor.parent
        }
    }
}
