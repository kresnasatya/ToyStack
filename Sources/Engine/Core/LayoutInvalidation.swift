import Foundation

@MainActor
enum LayoutInvalidation {

    static func childrenChanged(_ node: any DOMNode) {
        nearestBlock(node)?.markChildrenDirty()
    }

    static func childrenAppend(_ parent: any DOMNode, _ child: any DOMNode) {
        guard let block = parent.layoutObject as? BlockLayout else {
            childrenChanged(parent)
            return
        }
        block.noteAppendedChildren([child])
    }

    static func childrenInsert(
        _ parent: any DOMNode,
        _ child: any DOMNode,
        before reference: any DOMNode
    ) {
        guard let block = parent.layoutObject as? BlockLayout else {
            childrenChanged(parent)
            return
        }
        block.noteInsertedChildren([child], before: reference)
    }

    static func textChanged(_ node: TextNode) {
        childrenChanged(node)
    }

    static func attributesChanged(_ node: Element) {
        childrenChanged(node)
    }

    static func animatedPropertyChanged(_ node: any DOMNode, property: String) {
        let affectsSiblings: Bool = property == "display"
            || property == "position"
            || property == "margin-bottom"
        markLayoutInput(node, affectsSiblings: affectsSiblings)
    }

    private static func markLayoutInput(_ node: any DOMNode, affectsSiblings: Bool) {
        guard let block = nearestBlock(node) else { return }
        block.markChildrenDirty()

        guard affectsSiblings else { return }
        parentBlock(of: block)?.markChildrenDirty()
    }

    static func imageChanged(_ node: Element) {
        if let image = node.layoutObject as? ImageLayout {
            image.widthField.mark()
            image.heightField.mark()
        }
        childrenChanged(node)
    }

    static func nearestBlock(_ node: any DOMNode) -> BlockLayout? {
        var object: (any LayoutObject)? = node.layoutObject
        while let current = object {
            if let block = current as? BlockLayout {
                return block
            }
            object = current.parent
        }
        var dom: (any DOMNode)? = node.parent
        while let current = dom {
            if let block = current.layoutObject as? BlockLayout {
                return block
            }
            dom = current.parent
        }
        return nil
    }

    private static func parentBlock(of block: BlockLayout) -> BlockLayout? {
        var object: (any LayoutObject)? = block.parent
        while let current = object {
            if let parent = current as? BlockLayout { return parent }
            object = current.parent
        }
        return nil
    }
}
