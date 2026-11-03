import Foundation

// MARK: - LayoutInputsBuilder

/// Copies the DOM facts layout reads. The only layout-side code that needs the
/// document, so passes can move to values one file at a time.
@MainActor
enum LayoutInputsBuilder {
    static func build(dom: DOMTree) -> LayoutInputs {
        var nodes: [LayoutInput?] = []
        dom.forEachNode { id in
            guard let node: DOMNode = dom.node(id) else { return }
            while nodes.count <= Int(id.raw) { nodes.append(nil) }
            let element: ElementData? = node.element
            let ref: DOMRef = dom.ref(id)
            nodes[Int(id.raw)] = LayoutInput(
                identity: LayoutInputIdentity(
                    parent: dom.parent(of: id),
                    children: dom.children(of: id)
                ),
                content: LayoutInputContent(
                    tag: element?.tag,
                    attributes: element?.attributes ?? [:],
                    text: node.text?.text
                ),
                style: node.base.style.computed,
                font: ref.inheritedStyleOwner.style.computed.text.font,
                isChecked: element?.isChecked ?? false
            )
        }
        return LayoutInputs(nodes: nodes)
    }
}
