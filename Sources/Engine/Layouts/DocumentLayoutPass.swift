import CoreGraphics

// MARK: - DocumentLayoutPass

extension LayoutTree {
    func documentLayoutNeeded(_ root: LayoutRef) -> Bool {
        if root.hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        if root.tree.isDirty(.zoom, at: root.id)
            || root.tree.isDirty(.x, at: root.id)
            || root.tree.isDirty(.y, at: root.id)
            || root.tree.isDirty(.width, at: root.id)
            || root.tree.isDirty(.height, at: root.id)
        {
            return true
        }
        return root.tree.isDirty(.children, at: root.id)
    }

    func layoutDocument(
        availableWidth: CGFloat,
        zoom: CGFloat,
        pageZoom: CGFloat
    ) {
        let root: LayoutRef = self.root
        guard documentLayoutNeeded(root) else { return }
        defer { root.hasDirtyDescendants = false }

        root.zoomField.set(zoom)
        var data: DocumentData = root.documentData
        data.pageZoom = pageZoom
        root.documentData = data

        let child: LayoutRef
        if let existing: LayoutRef = root.childrenField.peek()?.first.map({ LayoutRef(id: $0, tree: self) }),
            existing.isBlock,
            existing.domNode == root.domNode
        {
            child = existing
        } else {
            child = LayoutRef(
                id: makeBlock(dom: root.domNode, parent: root.id, previous: nil),
                tree: self
            )
        }
        root.children = [child]

        let rootZoom: CGFloat = root.zoomField.read(notify: root.widthField)
        root.width = availableWidth - 2 * HSTEP * rootZoom
        root.x = HSTEP * root.zoomField.read(notify: root.xField)
        root.y = VSTEP * root.zoomField.read(notify: root.yField)

        child.layout()

        root.heightField.setDependencies([
            child.heightField,
            child.node.style.field(.paddingTop),
            child.node.style.field(.paddingBottom),
        ])
        root.height = boxHeight(child, notify: root.heightField)
    }
}
