import Foundation

@MainActor
enum LayoutInvalidation {

    static func childrenChanged(_ node: DOMRef) {
        guard let block = nearestBlock(node) else { return }
        block.box.tree.blockMarkChildrenDirty(block.id)
    }

    static func childrenAppend(_ parent: DOMRef, _ child: DOMRef) {
        guard let block = nearestBlock(parent), block.box.tree.isBlock(block.id) else {
            childrenChanged(parent)
            return
        }
        block.box.tree.blockNoteAppendedChildren(block.id, [child.id])
    }

    static func childrenInsert(
        _ parent: DOMRef,
        _ child: DOMRef,
        before reference: DOMRef
    ) {
        guard let block = nearestBlock(parent), block.box.tree.isBlock(block.id) else {
            childrenChanged(parent)
            return
        }
        block.box.tree.blockNoteInsertedChildren(block.id, [child.id], before: reference.id)
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
        block.box.tree.blockMarkChildrenDirty(block.id)

        guard affectsSiblings else { return }
        guard let parent = parentBlock(of: block) else { return }
        parent.box.tree.blockMarkChildrenDirty(parent.id)
    }

    static func imageChanged(_ node: DOMRef) {
        if let box: LayoutBox = node.dom.layoutBox,
            let id: LayoutID = node.layoutID,
            case .embed(.image) = box.tree.kind(id)
        {
            box.tree.markField(.width, at: id)
            box.tree.markField(.height, at: id)
        }
        childrenChanged(node)
    }

    static func nearestBlock(_ node: DOMRef) -> (box: LayoutBox, id: LayoutID)? {
        guard let box: LayoutBox = node.dom.layoutBox else { return nil }
        var current: LayoutID? = node.layoutID
        while let id = current {
            if box.tree.isBlock(id) {
                return (box, id)
            }
            current = box.tree.parentID(of: id)
        }
        var dom: DOMRef? = node.parent
        while let parent = dom {
            if let id = parent.layoutID, box.tree.isBlock(id) {
                return (box, id)
            }
            dom = parent.parent
        }
        return nil
    }

    private static func parentBlock(of block: (box: LayoutBox, id: LayoutID)) -> (box: LayoutBox, id: LayoutID)? {
        var current: LayoutID? = block.box.tree.parentID(of: block.id)
        while let id = current {
            if block.box.tree.isBlock(id) { return (block.box, id) }
            current = block.box.tree.parentID(of: id)
        }
        return nil
    }
}
