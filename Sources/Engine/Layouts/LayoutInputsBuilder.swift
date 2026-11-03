import Foundation

// MARK: - LayoutInputsBuilder

/// Copies the DOM facts layout reads. The only layout-side code that needs the
/// document, so passes can move to values one file at a time.
@MainActor
enum LayoutInputsBuilder {
    static func build(dom: DOMTree) -> LayoutInputs {
        var nodes: [LayoutInput?] = []
        var styleChanges: [NodeID: Set<StyleProperty>] = [:]
        dom.forEachNode { id in
            guard let node: DOMNode = dom.node(id) else { return }
            while nodes.count <= Int(id.raw) { nodes.append(nil) }
            let element: ElementData? = node.element
            let ref: DOMRef = dom.ref(id)
            let elementRef: ElementRef? = ref.element
            let changes: Set<StyleProperty> = node.base.style.takeLayoutChanges()
            if !changes.isEmpty { styleChanges[id] = changes }
            nodes[Int(id.raw)] = LayoutInput(
                node: LayoutInputNode(
                    parent: dom.parent(of: id),
                    children: dom.children(of: id),
                    isFocused: ref.isFocused,
                    isFocusVisible: ref.isFocusVisible
                ),
                content: LayoutInputContent(
                    tag: element?.tag,
                    attributes: element?.attributes ?? [:],
                    text: node.text?.text,
                    isChecked: element?.isChecked ?? false
                ),
                style: LayoutInputStyle(
                    computed: node.base.style.computed,
                    font: ref.inheritedStyleOwner.style.computed.text.font,
                    revision: node.base.style.revision
                ),
                media: LayoutInputMedia(
                    image: elementRef?.image,
                    isIframe: element?.tag == "iframe",
                    isCanvas: element?.tag == "canvas",
                    forcedColors: usesForcedColors(ref)
                )
            )
        }
        return LayoutInputs(
            nodes: nodes,
            scrollOffsets: dom.side.scrollOffsets,
            styleChanges: styleChanges
        )
    }
}
