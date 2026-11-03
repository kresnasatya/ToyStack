import Foundation

@MainActor
enum LayoutInvalidation {

    static func childrenChanged(_ node: DOMRef) {
        guard let block = nearestBlock(node) else { return }
        block.tree.blockMarkChildrenDirty(block.id)
    }

    static func childrenAppend(_ parent: DOMRef, _ child: DOMRef) {
        guard let block = nearestBlock(parent), block.isBlock else {
            childrenChanged(parent)
            return
        }
        block.tree.blockNoteAppendedChildren(block.id, [child])
    }

    static func childrenInsert(
        _ parent: DOMRef,
        _ child: DOMRef,
        before reference: DOMRef
    ) {
        guard let block = nearestBlock(parent), block.isBlock else {
            childrenChanged(parent)
            return
        }
        block.tree.blockNoteInsertedChildren(block.id, [child], before: reference)
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
        if let layout = node.layout, case .embed(.image) = layout.kind {
            layout.tree.markField(.width, at: layout.id)
            layout.tree.markField(.height, at: layout.id)
        }
        childrenChanged(node)
    }

    static func nearestBlock(_ node: DOMRef) -> LayoutRef? {
        var layout: LayoutRef? = node.layout
        while let current = layout {
            if current.isBlock {
                return current
            }
            layout = current.parent
        }
        var dom: DOMRef? = node.parent
        while let current = dom {
            if let resolved = current.layout, resolved.isBlock {
                return resolved
            }
            dom = current.parent
        }
        return nil
    }

    private static func parentBlock(of block: LayoutRef) -> LayoutRef? {
        var layout: LayoutRef? = block.parent
        while let current = layout {
            if current.isBlock { return current }
            layout = current.parent
        }
        return nil
    }
}
