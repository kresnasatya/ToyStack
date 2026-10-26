import Foundation

@MainActor
enum LayoutInvalidation {

    static func childrenChanged(_ node: any DOMNode) {
        nearestBlock(node)?.markChildrenDirty()
    }

    static func textChanged(_ node: TextNode) {
        childrenChanged(node)
    }

    static func attributesChanged(_ node: Element) {
        childrenChanged(node)
    }

    static func styleChanged(_ node: any DOMNode, old: [String: String], new: [String: String]) {
        guard let block = nearestBlock(node) else { return }
        block.markChildrenDirty()

        let regroupped: Bool = old["display"] != new["display"] || old["position"] != new["position"]
        guard regroupped else { return }
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
