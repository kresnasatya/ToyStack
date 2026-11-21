import Foundation

// MARK: - LayoutInputsBuilder

/// The only layout-side code that needs the document, so passes can move to
/// values one file at a time.
@MainActor
enum LayoutInputsBuilder {
    static func build(dom: DOMTree) -> LayoutInputs {
        return build(dom: dom, previous: nil)
    }

    /// Starts from `previous` and rebuilds only the nodes the document changed
    /// after `previous` was built. An image change still rebuilds everything:
    /// images are not stamped per node.
    static func build(dom: DOMTree, previous: LayoutInputs?) -> LayoutInputs {
        let reusable: LayoutInputs?
        let baseline: UInt64
        if let previous, let key: LayoutInputsKey = previous.key,
            key.dom == ObjectIdentifier(dom),
            key.imageRevision == dom.side.images.revision
        {
            reusable = previous
            baseline = key.domRevision
        } else {
            reusable = nil
            baseline = 0
        }
        var nodes: [LayoutInput?] = reusable?.nodes ?? []
        // Changes the previous inputs still hold have not reached a pass yet.
        var styleChanges: [NodeID: Set<StyleProperty>] = reusable?.styleChanges ?? [:]
        let count: Int = dom.nodeCount
        if nodes.count < count {
            nodes.append(contentsOf: repeatElement(nil, count: count - nodes.count))
        }
        var restyled: [NodeID] = []
        var touched: Int = 0
        for index in 0..<count {
            let id: NodeID = NodeID(raw: UInt32(index))
            // Revisions are compared before the node is read: most nodes are
            // unchanged, and reading each one cost more than the whole rebuild.
            let unchanged: Bool = dom.changeRevision(of: id) <= baseline
            if unchanged, let oldRevision: UInt64 = nodes[index]?.style.revision,
                oldRevision == dom.styleRevision(of: id)
            {
                continue
            }
            guard let node: DOMNode = dom.node(id) else { continue }
            touched += 1
            let changes: Set<StyleProperty> = node.base.style.takeLayoutChanges()
            if !changes.isEmpty { styleChanges[id, default: []].formUnion(changes) }
            if node.element != nil { restyled.append(id) }
            let font: TextStyle.Font
            if node.text != nil, let parent: NodeID = node.base.parent,
                let parentNode: DOMNode = dom.node(parent)
            {
                font = parentNode.base.style.computed.text.font
            } else {
                font = node.base.style.computed.text.font
            }
            if unchanged, let old: LayoutInput = nodes[index] {
                let style: LayoutInputStyle = LayoutInputStyle(
                    computed: node.base.style.computed,
                    font: font,
                    revision: node.base.style.revision
                )
                nodes[index] = old.restyled(style, forcedColors: usesForcedColors(dom.ref(id)))
                profiler.count("layout.inputs.style")
                continue
            }
            profiler.count("layout.inputs.rebuilt")
            let element: ElementData? = node.element
            let ref: DOMRef = dom.ref(id)
            let elementRef: ElementRef? = ref.element
            nodes[index] = LayoutInput(
                node: LayoutInputNode(
                    parent: dom.parent(of: id),
                    children: renderedChildren(of: id, in: dom),
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
        for parent in restyled {
            refreshTextFonts(of: parent, in: dom, nodes: &nodes)
        }
        if count > touched {
            profiler.count("layout.inputs.reused", by: count - touched)
        }
        return LayoutInputs(
            nodes: nodes,
            styleChanges: styleChanges,
            key: LayoutInputsKey(
                dom: ObjectIdentifier(dom),
                domRevision: dom.revision,
                imageRevision: dom.side.images.revision,
                styleRevision: StyleRevision.epoch
            )
        )
    }

    /// A text node takes its font from its parent, and the parent's font can
    /// change while the text node's own style does not (a font animation
    /// writes the parent alone), so restyled parents pass their font down.
    private static func refreshTextFonts(of parent: NodeID, in dom: DOMTree, nodes: inout [LayoutInput?]) {
        guard let font: TextStyle.Font = nodes[Int(parent.raw)]?.style.computed.text.font else { return }
        for child in dom.children(of: parent) where dom.isText(child) {
            let index: Int = Int(child.raw)
            guard index < nodes.count, let current: LayoutInput = nodes[index], current.style.font != font
            else { continue }
            var style: LayoutInputStyle = current.style
            style.font = font
            nodes[index] = current.restyled(style, forcedColors: current.media.forcedColors)
        }
    }

    // Comments stay in the DOM for scripts to walk, but they never get a box.
    private static func renderedChildren(of id: NodeID, in dom: DOMTree) -> [NodeID] {
        let children: [NodeID] = dom.children(of: id)
        guard children.contains(where: { dom.isComment($0) }) else { return children }
        return children.filter({ !dom.isComment($0) })
    }
}
