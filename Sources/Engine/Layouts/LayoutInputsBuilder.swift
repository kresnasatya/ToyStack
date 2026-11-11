import Foundation

// MARK: - LayoutInputsBuilder

/// The only layout-side code that needs the document, so passes can move to
/// values one file at a time.
@MainActor
enum LayoutInputsBuilder {
    static func build(dom: DOMTree) -> LayoutInputs {
        return build(dom: dom, previous: nil, key: nil)
    }

    static func build(
        dom: DOMTree,
        previous: LayoutInputs?,
        key: LayoutInputsKey?
    ) -> LayoutInputs {
        let reusable: LayoutInputs?
        if let key: LayoutInputsKey = key,
            key.dom == ObjectIdentifier(dom),
            key.domRevision == dom.revision,
            key.imageRevision == dom.side.images.revision
        {
            reusable = previous
        } else {
            reusable = nil
        }
        var nodes: [LayoutInput?] = reusable?.nodes ?? []
        var styleChanges: [NodeID: Set<StyleProperty>] = [:]
        dom.forEachNode { id in
            guard let node: DOMNode = dom.node(id) else { return }
            while nodes.count <= Int(id.raw) { nodes.append(nil) }
            let revision: UInt64 = node.base.style.revision
            let old: LayoutInput? = reusable?.input(id)
            if let old, old.style.revision == revision {
                if node.text == nil {
                    profiler.count("layout.inputs.reused")
                    return
                }
                if let parent: NodeID = node.base.parent,
                    let parentNode: DOMNode = dom.node(parent),
                    old.style.font == parentNode.base.style.computed.text.font
                {
                    profiler.count("layout.inputs.reused")
                    return
                }
            }
            let changes: Set<StyleProperty> = node.base.style.takeLayoutChanges()
            if !changes.isEmpty { styleChanges[id] = changes }
            let font: TextStyle.Font
            if node.text != nil, let parent: NodeID = node.base.parent,
                let parentNode: DOMNode = dom.node(parent)
            {
                font = parentNode.base.style.computed.text.font
            } else {
                font = node.base.style.computed.text.font
            }
            if let old {
                var updated: LayoutInput = old
                updated.style = LayoutInputStyle(
                    computed: node.base.style.computed,
                    font: font,
                    revision: revision
                )
                nodes[Int(id.raw)] = updated
                profiler.count("layout.inputs.style")
                return
            }
            profiler.count("layout.inputs.rebuilt")
            let element: ElementData? = node.element
            let ref: DOMRef = dom.ref(id)
            let elementRef: ElementRef? = ref.element
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
                    font: font,
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
            styleChanges: styleChanges
        )
    }
}
