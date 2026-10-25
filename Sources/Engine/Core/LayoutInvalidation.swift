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
}
