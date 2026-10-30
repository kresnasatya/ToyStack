import CoreGraphics

// MARK: DocumentLayout
@MainActor
class DocumentLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)? = nil
    var fields: LayoutFieldStore = LayoutFieldStore()
    var hasDirtyDescendants: Bool = false
    var pageZoom: CGFloat = 1.0

    init(node: any DOMNode) {
        self.node = node
        zoomField.setDependencies([])
        widthField.setDependencies([zoomField])
        xField.setDependencies([zoomField])
        yField.setDependencies([zoomField])
        childrenField.setDependencies([])
    }

    func layout() {
        layout(availableWidth: WIDTH)
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        if zoomField.dirty || xField.dirty || yField.dirty
            || widthField.dirty || heightField.dirty
        {
            return true
        }
        return childrenField.dirty
    }

    func layout(availableWidth: CGFloat = WIDTH, zoom: CGFloat = 1.0, pageZoom: CGFloat = 1.0) {
        if !layoutNeeded() {
            return
        }
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
        heightField.setDependencies([
            child.heightField,
            child.node.style.field("padding-top"),
            child.node.style.field("padding-bottom"),
        ])
        heightField.set(child.boxHeight(notify: heightField))
    }

    func paint(into items: inout [any DisplayItem]) { }
    func shouldPaint() -> Bool {
        true
    }
}
