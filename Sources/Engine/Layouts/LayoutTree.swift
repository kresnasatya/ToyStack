import CoreGraphics
import Foundation

// MARK: - LayoutTree

/// Arena of layout nodes. One tree belongs to one document (`DOMTree`).
///
/// Nodes are append-only: removing a subtree writes `nil` into the hole and
/// never reuses the ID, so a stale `LayoutID` cannot point at another node.
@MainActor
final class LayoutTree {
    private(set) var nodes: [LayoutNode?] = []
    let dom: DOMTree
    private(set) var primaryByNode: [NodeID: LayoutID] = [:]
    var dependencies: DependencyIndex = DependencyIndex()

    init(dom: DOMTree) {
        self.dom = dom
        dom.layoutTree = self
        dom.attachLayoutTree(self)
        self.nodes.reserveCapacity(1024)
        let document: LayoutID = append(
            kind: .document(DocumentData(pageZoom: 1)),
            dom: dom.root,
            parent: nil,
            previous: nil
        )
        assert(document.raw == 0)
        primaryByNode[dom.root] = document
        let root: LayoutRef = LayoutRef(id: document, tree: self)
        root.zoomField.setDependencies([])
        root.widthField.setDependencies([root.zoomField])
        root.xField.setDependencies([root.zoomField])
        root.yField.setDependencies([root.zoomField])
        root.childrenField.setDependencies([])
    }

    // MARK: - Identity

    func append(
        kind: LayoutKind,
        dom: NodeID,
        parent: LayoutID?,
        previous: LayoutID?
    ) -> LayoutID {
        let id: LayoutID = LayoutID(raw: nodes.count)
        let links: LayoutLinks = LayoutLinks(
            parent: parent,
            previous: previous,
            children: [],
            versions: LinkVersions(children: 0, previous: 0)
        )
        let state: LayoutState = LayoutState(
            fields: LayoutFieldStore(),
            hasDirtyDescendants: false
        )
        nodes.append(LayoutNode(kind: kind, dom: dom, links: links, state: state))
        return id
    }

    func setPrimary(_ id: LayoutID, for node: NodeID) {
        primaryByNode[node] = id
    }

    func primaryLayout(for node: NodeID) -> LayoutID? {
        return primaryByNode[node]
    }

    var root: LayoutRef {
        return LayoutRef(id: LayoutID(raw: 0), tree: self)
    }

    func markDocumentWidthDirty() {
        root.widthField.mark()
    }

    func markDocumentGeometryDirty() {
        root.widthField.mark()
        root.zoomField.mark()
    }

    func documentNeedsLayout() -> Bool {
        return documentLayoutNeeded(root)
    }

    var liveIDs: [LayoutID] {
        var ids: [LayoutID] = []
        ids.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() where node != nil {
            ids.append(LayoutID(raw: index))
        }
        return ids
    }

    func node(_ id: LayoutID) -> LayoutNode {
        guard let node: LayoutNode = nodes[id.raw] else {
            preconditionFailure("LayoutID points at a removed node")
        }
        return node
    }

    func kind(_ id: LayoutID) -> LayoutKind {
        return node(id).kind
    }

    func contains(_ id: LayoutID) -> Bool {
        guard id.raw >= 0, id.raw < nodes.count else { return false }
        return nodes[id.raw] != nil
    }

    func setKind(_ kind: LayoutKind, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.kind = kind
        nodes[id.raw] = node
    }

    // MARK: - Links

    func children(of id: LayoutID) -> [LayoutID] {
        return node(id).links.children
    }

    func setChildren(_ children: [LayoutID], of id: LayoutID) {
        var parent: LayoutNode = node(id)
        parent.links.children = children
        parent.links.versions.children += 1
        nodes[id.raw] = parent
        for child in children {
            var node: LayoutNode = self.node(child)
            node.links.parent = id
            nodes[child.raw] = node
        }
    }

    func setPrevious(_ previous: LayoutID?, of id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.links.previous = previous
        node.links.versions.previous += 1
        nodes[id.raw] = node
    }

    func removeSubtree(_ id: LayoutID) {
        guard nodes[id.raw] != nil else { return }
        let links: LayoutLinks = node(id).links
        if let parent: LayoutID = links.parent {
            var node: LayoutNode = self.node(parent)
            node.links.children.removeAll(where: { $0 == id })
            node.links.versions.children += 1
            nodes[parent.raw] = node
        }
        removeRecursively(id)
    }

    private func removeRecursively(_ id: LayoutID) {
        guard let node: LayoutNode = nodes[id.raw] else { return }
        for child in node.links.children {
            removeRecursively(child)
        }
        if let primary: LayoutID = primaryByNode[node.dom], primary == id {
            primaryByNode.removeValue(forKey: node.dom)
        }
        nodes[id.raw] = nil
    }

    /// Frees nodes that are no longer reachable from the document root.
    /// Returns the dropped IDs, so callers can invalidate caches that may
    /// still hold them.
    @discardableResult
    func sweepUnreachable() -> Set<LayoutID> {
        var reachable: Set<LayoutID> = []
        collectReachable(root.id, into: &reachable)
        var removed: Set<LayoutID> = []
        for index in nodes.indices {
            guard let node: LayoutNode = nodes[index] else { continue }
            let id: LayoutID = LayoutID(raw: index)
            if reachable.contains(id) { continue }
            if let primary: LayoutID = primaryByNode[node.dom], primary == id {
                primaryByNode.removeValue(forKey: node.dom)
            }
            nodes[index] = nil
            removed.insert(id)
        }
        return removed
    }

    private func collectReachable(_ id: LayoutID, into reachable: inout Set<LayoutID>) {
        guard nodes[id.raw] != nil, !reachable.contains(id) else { return }
        reachable.insert(id)
        for child in node(id).links.children {
            collectReachable(child, into: &reachable)
        }
    }

    // MARK: - Fields
    func isDirty(_ field: LayoutField, at id: LayoutID) -> Bool {
        return node(id).state.fields.isDirty(field)
    }

    func isUsed(_ field: LayoutField, at id: LayoutID) -> Bool {
        return node(id).state.fields.isUsed(field)
    }

    func isFrozen(_ field: LayoutField, at id: LayoutID) -> Bool {
        return node(id).state.fields.isFrozen(field)
    }

    func markUsed(_ field: LayoutField, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.markUsed(field)
        nodes[id.raw] = node
    }

    func markClean(_ field: LayoutField, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.markClean(field)
        nodes[id.raw] = node
    }

    func markFrozen(_ field: LayoutField, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.markFrozen(field)
        nodes[id.raw] = node
    }

    func markField(_ field: LayoutField, at id: LayoutID) {
        guard !isDirty(field, at: id) else { return }
        profiler.count("layout.field.mark")
        var node: LayoutNode = self.node(id)
        node.state.fields.markDirty(field)
        nodes[id.raw] = node
        markAncestorsDirty(from: id)
    }

    func markDependents(_ key: FieldKey) {
        for ref in dependencies.mark(key) {
            ref.mark()
        }
    }

    func markAncestorsDirty(from id: LayoutID) {
        var current: LayoutID? = node(id).links.parent
        while let ancestor = current, !node(ancestor).state.hasDirtyDescendants {
            var node: LayoutNode = self.node(ancestor)
            node.state.hasDirtyDescendants = true
            nodes[ancestor.raw] = node
            current = node.links.parent
        }
    }

    func setDirtyDescendants(_ value: Bool, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.hasDirtyDescendants = value
        nodes[id.raw] = node
    }

    // MARK: - Values

    func writeCGFloat(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        var node: LayoutNode = self.node(id)
        switch field {
        case .x:
            node.state.fields.geometry.origin.x = value
        case .y:
            node.state.fields.geometry.origin.y = value
        case .width:
            node.state.fields.geometry.size.width = value
        case .height:
            node.state.fields.geometry.size.height = value
        case .zoom:
            node.state.fields.geometry.zoom = value
        case .ascent:
            node.state.fields.inlineText.ascent = value
        case .descent:
            node.state.fields.inlineText.descent = value
        default:
            preconditionFailure("Field \(field.rawValue) is not a CGFloat value")
        }
        nodes[id.raw] = node
    }

    func writeFont(_ font: BrowserFont, for id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.inlineText.font = font
        nodes[id.raw] = node
    }

    func writeInlineContent(_ value: UInt64, for id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.inlineText.inlineContent = value
        nodes[id.raw] = node
    }

    func setField(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        writeCGFloat(field, value, for: id)
        markUsed(field, at: id)
        markClean(field, at: id)
    }

    func setFont(_ font: BrowserFont, for id: LayoutID) {
        writeFont(font, for: id)
        markUsed(.font, at: id)
        markClean(.font, at: id)
    }
}
