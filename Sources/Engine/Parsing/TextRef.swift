import Foundation

/// Text-only view over a `DOMRef`.
@MainActor
struct TextRef {
    let ref: DOMRef
}

extension TextRef {
    private var textNode: TextNode {
        guard let textNode: TextNode = ref.dom.node(ref.id) as? TextNode else {
            preconditionFailure("TextRef points at an element")
        }
        return textNode
    }

    var text: String { textNode.text }

    func append(_ suffix: String) {
        textNode.append(suffix)
        LayoutInvalidation.textChanged(ref)
    }
}
