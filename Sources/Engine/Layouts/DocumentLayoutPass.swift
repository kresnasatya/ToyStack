import CoreGraphics

// MARK: - DocumentLayoutPass

extension LayoutTree {
    func documentLayoutNeeded(_ id: LayoutID) -> Bool {
        if hasDirtyDescendants(at: id) {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        if isDirty(.zoom, at: id)
            || isDirty(.x, at: id)
            || isDirty(.y, at: id)
            || isDirty(.width, at: id)
            || isDirty(.height, at: id)
        {
            return true
        }
        return isDirty(.children, at: id)
    }

    mutating func layoutDocument(
        availableWidth: CGFloat,
        zoom: CGFloat,
        pageZoom: CGFloat
    ) {
        let root: LayoutID = rootID
        consumeStyleChanges()
        guard documentLayoutNeeded(root) else { return }
        dependencies.beginLayout()
        defer {
            setDirtyDescendants(false, at: root)
            dependencies.endLayout(from: self)
        }

        setField(.zoom, zoom, for: root)
        var data: DocumentData = documentData(root)
        data.pageZoom = pageZoom
        setKind(.document(data), at: root)

        let dom: NodeID = domID(of: root)
        let child: LayoutID
        if let existing: LayoutID = childrenIDs(of: root).first,
            isBlock(existing),
            domID(of: existing) == dom
        {
            child = existing
        } else {
            child = makeBlock(dom: dom, parent: root, previous: nil)
        }
        setChildrenField([child], of: root)

        let rootZoom: CGFloat = zoom
        setField(.width, availableWidth - 2 * HSTEP * rootZoom, for: root)
        setField(.x, HSTEP * rootZoom, for: root)
        setField(.y, VSTEP * rootZoom, for: root)

        layout(child)

        markUsed(.height, at: root)
        setField(.height, boxHeight(child), for: root)
    }
}
