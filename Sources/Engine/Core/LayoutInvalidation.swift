import Foundation

@MainActor
enum LayoutInvalidation {

    static func childrenChanged(_ node: DOMRef) {
        perform(.childrenChanged(node.id), in: node.dom)
    }

    static func childrenAppend(_ parent: DOMRef, _ child: DOMRef) {
        guard let block = nearestBlock(parent), block.box.tree.isBlock(block.id) else {
            childrenChanged(parent)
            return
        }
        // A pass running now may already have read the new child from the
        // DOM, so the replay rebuilds the children instead of appending twice.
        block.box.record(.childrenChanged(parent.id))
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
        block.box.record(.childrenChanged(parent.id))
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
        perform(.layoutInputChanged(node.id, affectsSiblings: affectsSiblings), in: node.dom)
    }

    static func imageChanged(_ node: DOMRef) {
        perform(.imageChanged(node.id), in: node.dom)
    }

    /// Marks `edit` on the tree the DOM's layout box holds now.
    static func apply(_ edit: LayoutEdit, in dom: DOMTree) {
        switch edit {
        case .childrenChanged(let id):
            markChildren(dom.ref(id))
        case .imageChanged(let id):
            markImage(dom.ref(id))
        case .layoutInputChanged(let id, let affectsSiblings):
            markLayoutInput(dom.ref(id), affectsSiblings: affectsSiblings)
        }
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

    // MARK: - Marking

    private static func perform(_ edit: LayoutEdit, in dom: DOMTree) {
        dom.layoutBox?.record(edit)
        apply(edit, in: dom)
    }

    private static func markChildren(_ node: DOMRef) {
        guard let block = nearestBlock(node) else { return }
        block.box.tree.blockMarkChildrenDirty(block.id)
    }

    private static func markImage(_ node: DOMRef) {
        if let box: LayoutBox = node.dom.layoutBox,
            let id: LayoutID = node.layoutID,
            case .embed(.image) = box.tree.kind(id)
        {
            box.tree.markField(.width, at: id)
            box.tree.markField(.height, at: id)
        }
        markChildren(node)
    }

    private static func markLayoutInput(_ node: DOMRef, affectsSiblings: Bool) {
        guard let block = nearestBlock(node) else { return }
        block.box.tree.blockMarkChildrenDirty(block.id)

        guard affectsSiblings else { return }
        guard let parent = parentBlock(of: block) else { return }
        parent.box.tree.blockMarkChildrenDirty(parent.id)
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
