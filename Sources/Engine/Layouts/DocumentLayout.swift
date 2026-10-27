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
    let xField: ProtectedField<CGFloat>
    var x: CGFloat {
        get { xField.get() }
        set { xField.set(newValue) }
    }
    let yField: ProtectedField<CGFloat>
    var y: CGFloat {
        get { yField.get() }
        set { yField.set(newValue) }
    }
    let widthField: ProtectedField<CGFloat>
    var width: CGFloat {
        get { widthField.get() }
        set { widthField.set(newValue) }
    }
    let heightField: ProtectedField<CGFloat>
    var height: CGFloat {
        get { heightField.get() }
        set { heightField.set(newValue) }
    }
    let zoomField: ProtectedField<CGFloat>
    var zoom: CGFloat {
        get { zoomField.get() }
        set { zoomField.set(newValue) }
    }
    var pageZoom: CGFloat = 1.0

    init(node: any DOMNode) {
        self.zoomField = ProtectedField("zoom", node: node)
        self.widthField = ProtectedField("width", node: node)
        self.heightField = ProtectedField("height", node: node)
        self.xField = ProtectedField("x", node: node)
        self.yField = ProtectedField("y", node: node)
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

    func layout(availableWidth: CGFloat = WIDTH, zoom: CGFloat = 1.0, pageZoom: CGFloat = 1.0) {
        defer { hasDirtyDescendants = false }
        zoomField.set(zoom)
        self.pageZoom = pageZoom
        let child: BlockLayout
        if let existing = childrenField.peek()?.first as? BlockLayout,
            existing.node === node
        {
            child = existing
        } else {
            child = BlockLayout(node: node, parent: self, previous: nil)
        }
        children = [child]

        let rootZoom: CGFloat = zoomField.read(notify: widthField)
        widthField.set(availableWidth - 2 * HSTEP * rootZoom)
        xField.set(HSTEP * zoomField.read(notify: xField))
        yField.set(VSTEP * zoomField.read(notify: yField))

        child.layout()
        heightField.copy(from: child.heightField)
    }

    func paint(into items: inout [any DisplayItem]) { }
    func shouldPaint() -> Bool {
        true
    }
}
