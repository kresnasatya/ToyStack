import CoreGraphics

// MARK: DocumentLayout
@MainActor
class DocumentLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)? = nil
    private let childrenField: ProtectedField<[any LayoutObject]>
    var children: [any LayoutObject] {
        get { childrenField.get() }
        set { childrenField.set(newValue) }
    }
    var hasDirtyDescendants: Bool = false
    var x: CGFloat = 0
    var y: CGFloat = 0
    let widthField: ProtectedField<CGFloat>
    var width: CGFloat {
        get { widthField.get() }
        set { widthField.set(newValue) }
    }
    var height: CGFloat = 0
    let zoomField: ProtectedField<CGFloat>
    var zoom: CGFloat {
        get { zoomField.get() }
        set { zoomField.set(newValue) }
    }
    var pageZoom: CGFloat = 1.0

    init(node: any DOMNode) {
        self.zoomField = ProtectedField("zoom", node: node)
        self.widthField = ProtectedField("width", node: node)
        self.childrenField = ProtectedField(
            owner: FieldOwner(name: "children", node: node),
            equals: { lhs, rhs in
                guard lhs.count == rhs.count else { return false }
                return zip(lhs, rhs).allSatisfy({ pair in pair.0 === pair.1 })
            }
        )
        self.node = node
    }

    func layout() {
        layout(availableWidth: WIDTH)
    }

    func layout(reusesChildren: Bool) {
        layout(availableWidth: WIDTH, zoom: zoom, pageZoom: pageZoom, reusesChildren: reusesChildren)
    }

    func layout(availableWidth: CGFloat = WIDTH, zoom: CGFloat = 1.0, pageZoom: CGFloat = 1.0, reusesChildren: Bool = false) {
        zoomField.set(zoom)
        self.pageZoom = pageZoom
        let child: BlockLayout
        if reusesChildren,
            let existing = childrenField.peek()?.first as? BlockLayout,
            existing.node === node
        {
            child = existing
        } else {
            child = BlockLayout(node: node, parent: self, previous: nil)
        }
        children = [child]

        let rootZoom: CGFloat = zoomField.read(notify: widthField)
        widthField.set(availableWidth - 2 * HSTEP * rootZoom)
        x = scaled(HSTEP)
        y = scaled(VSTEP)

        child.layout(reusesChildren: reusesChildren)
        height = child.height
    }

    func paint(into items: inout [any DisplayItem]) { }
    func shouldPaint() -> Bool {
        true
    }
}
