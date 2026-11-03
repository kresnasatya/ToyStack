import Foundation

@MainActor
enum LayoutInvalidation {

    static func childrenChanged(_ node: DOMRef) {
        guard let block = nearestBlock(node) else { return }
        block.tree.blockMarkChildrenDirty(block.id)
    }

    static func childrenAppend(_ parent: DOMRef, _ child: DOMRef) {
        guard let block = nearestBlock(parent), block.tree.isBlock(block.id) else {
            childrenChanged(parent)
            return
        }
        block.tree.blockNoteAppendedChildren(block.id, [child.id])
    }

    static func childrenInsert(
        _ parent: DOMRef,
        _ child: DOMRef,
        before reference: DOMRef
    ) {
        guard let block = nearestBlock(parent), block.tree.isBlock(block.id) else {
            childrenChanged(parent)
            return
        }
        block.tree.blockNoteInsertedChildren(block.id, [child.id], before: reference.id)
    }

    static func textChanged(_ node: DOMRef) {
        childrenChanged(node)
    }

    static func attributesChanged(_ node: DOMRef) {
        childrenChanged(node)
    }

    static func animatedPropertyChanged(_ node: DOMRef, property: StyleProperty) {
        let affectsSiblings: Bool = property == .display
            || property == .position
            || property == .marginBottom
        markLayoutInput(node, affectsSiblings: affectsSiblings)
    }

    private static func markLayoutInput(_ node: DOMRef, affectsSiblings: Bool) {
        guard let block = nearestBlock(node) else { return }
        block.tree.blockMarkChildrenDirty(block.id)

        guard affectsSiblings else { return }
        guard let parent = parentBlock(of: block) else { return }
        parent.tree.blockMarkChildrenDirty(parent.id)
    }

    static func imageChanged(_ node: DOMRef) {
        if let tree: LayoutTree = node.dom.layoutTree,
            let id: LayoutID = node.layoutID,
            case .embed(.image) = tree.kind(id)
        {
            tree.markField(.width, at: id)
            tree.markField(.height, at: id)
        }
        childrenChanged(node)
    }

    static func nearestBlock(_ node: DOMRef) -> (tree: LayoutTree, id: LayoutID)? {
        guard let tree: LayoutTree = node.dom.layoutTree else { return nil }
        var current: LayoutID? = node.layoutID
        while let id = current {
            if tree.isBlock(id) {
                return (tree, id)
            }
            current = tree.parentID(of: id)
        }
        var dom: DOMRef? = node.parent
        while let parent = dom {
            if let id = parent.layoutID, tree.isBlock(id) {
                return (tree, id)
            }
            dom = parent.parent
        }
        return nil
    }

    private static func parentBlock(of block: (tree: LayoutTree, id: LayoutID)) -> (tree: LayoutTree, id: LayoutID)? {
        var current: LayoutID? = block.tree.parentID(of: block.id)
        while let id = current {
            if block.tree.isBlock(id) { return (block.tree, id) }
            current = block.tree.parentID(of: id)
        }
        return nil
    }
}
