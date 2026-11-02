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
        self.nodes.reserveCapacity(1024)
        let document: LayoutID = append(
            kind: .document(DocumentData(pageZoom: 1)),
            dom: dom.root,
            parent: nil,
            previous: nil
        )
        assert(document.raw == 0)
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
            fields: ArenaFieldStore(),
            hasDirtyDescendants: false
        )
        nodes.append(LayoutNode(kind: kind, dom: dom, links: links, state: state))
        if primaryByNode[dom] == nil {
            primaryByNode[dom] = id
        }
        return id
    }

    func primaryLayout(for node: NodeID) -> LayoutID? {
        return primaryByNode[node]
    }

    func node(_ id: LayoutID) -> LayoutNode {
        guard let node: LayoutNode = nodes[id.raw] else {
            preconditionFailure("LayoutID points at a removed node")
        }
        return node
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

    // MARK: - Fields

    func isDirty(_ field: LayoutField, at id: LayoutID) -> Bool {
        return node(id).state.fields.isDirty(field)
    }

    func markField(_ field: LayoutField, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.markDirty(field)
        nodes[id.raw] = node
    }

    func setField(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
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
        default:
            preconditionFailure("Field \(field.rawValue) is not a geometry value")
        }
        node.state.fields.markUsed(field)
        node.state.fields.markClean(field)
        nodes[id.raw] = node
    }

    func setFont(_ font: BrowserFont, for id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.inlineText.font = font
        node.state.fields.markUsed(.font)
        node.state.fields.markClean(.font)
        nodes[id.raw] = node
    }
}
