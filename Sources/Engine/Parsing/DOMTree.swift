import Foundation

/// Temporary adapter that gives every node in an existing class tree a `NodeID`.
///
/// The arena storage replaces this index in phase C2. Until then the class tree
/// stays authoritative and `DOMRef` views look nodes up through this map.
@MainActor
final class DOMTree {
    private struct Index {
        var nodes: [NodeID: any DOMNode] = [:]
        var ids: [ObjectIdentifier: NodeID] = [:]
    }

    private var index: Index = Index()
    private var next: UInt32 = 0
    private(set) var root: NodeID

    init(root: any DOMNode) {
        self.root = NodeID(raw: 0)
        self.next = 1
        var index: Index = Index()
        index.nodes[self.root] = root
        index.ids[ObjectIdentifier(root)] = self.root
        self.index = index
        root.style.attachOwner(self.root)
        for child in root.children {
            adopt(child)
        }
    }

    func node(_ id: NodeID) -> (any DOMNode)? {
        return index.nodes[id]
    }

    func ref(_ node: any DOMNode) -> DOMRef {
        return DOMRef(id: id(of: node), dom: self)
    }

    func id(of node: any DOMNode) -> NodeID {
        if let id = index.ids[ObjectIdentifier(node)] { return id }
        return adopt(node)
    }

    /// Registers one node and stamps its style owner. Children are not visited.
    @discardableResult
    func register(_ node: any DOMNode) -> NodeID {
        if let existing = index.ids[ObjectIdentifier(node)] { return existing }
        let id: NodeID = NodeID(raw: next)
        next += 1
        index.nodes[id] = node
        index.ids[ObjectIdentifier(node)] = id
        node.style.attachOwner(id)
        return id
    }

    /// Registers a node and its whole subtree.
    @discardableResult
    func adopt(_ node: any DOMNode) -> NodeID {
        let id: NodeID = register(node)
        for child in node.children {
            adopt(child)
        }
        return id
    }
}
