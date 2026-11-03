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
        consumeStyleChanges()
        guard documentLayoutNeeded(root) else { return }
        dependencies.beginLayout()
        dependencies.rebuild(from: self)
        defer {
            root.hasDirtyDescendants = false
            dependencies.endLayout(from: self)
        }

        root.zoom = zoom
        var data: DocumentData = root.documentData
        data.pageZoom = pageZoom
        root.documentData = data

        let child: LayoutRef
        if let existing: LayoutRef = root.children.first,
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

        let rootZoom: CGFloat = root.zoom
        root.width = availableWidth - 2 * HSTEP * rootZoom
        root.x = HSTEP * root.zoom
        root.y = VSTEP * root.zoom

        child.layout()

        markUsed(.height, at: root.id)
        root.height = boxHeight(child.id)
    }
}
