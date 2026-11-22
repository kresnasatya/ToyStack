import Foundation

// MARK: - StyleSnapshotBuilder

@MainActor
enum StyleSnapshotBuilder {
    static func build(root: DOMRef) -> StyleSnapshot {
        return build(dom: root.dom)
    }

    static func build(dom: DOMTree) -> StyleSnapshot {
        var nodes: [StyleNode?] = []
        var indexByID: [NodeID: Int] = [:]
        dom.forEachNode { id in
            indexByID[id] = nodes.count
            nodes.append(nil)
        }
        dom.forEachNode { id in
            guard let index: Int = indexByID[id] else { return }
            nodes[index] = makeNode(id, dom: dom, indexByID: indexByID)
        }
        let root: Int = indexByID[dom.root] ?? 0
        return StyleSnapshot(nodes: nodes, indexByID: indexByID, root: root, revision: dom.revision)
    }

    static func update(_ snapshot: inout StyleSnapshot, dom: DOMTree) {
        guard snapshot.revision != dom.revision else { return }
        let baseline: UInt64 = snapshot.revision
        for raw in snapshot.nodes.count..<max(snapshot.nodes.count, dom.nodeCount) {
            snapshot.indexByID[NodeID(raw: UInt32(raw))] = snapshot.nodes.count
            snapshot.nodes.append(nil)
        }
        var updated: Int = 0
        for raw in 0..<dom.nodeCount {
            let id: NodeID = NodeID(raw: UInt32(raw))
            guard dom.changeRevision(of: id) > baseline,
                let index: Int = snapshot.indexByID[id]
            else { continue }
            snapshot.nodes[index] = makeNode(id, dom: dom, indexByID: snapshot.indexByID)
            updated += 1
        }
        if updated > 0 {
            profiler.count("style.snapshot.nodes.updated", by: updated)
        }
        snapshot.revision = dom.revision
    }

    private static func makeNode(_ id: NodeID, dom: DOMTree, indexByID: [NodeID: Int]) -> StyleNode? {
        guard dom.node(id) != nil else { return nil }
        let node: DOMRef = dom.ref(id)
        let element: ElementRef? = node.element
        let parent: Int? = dom.parent(of: id).flatMap({ indexByID[$0] })
        let children: [Int] = dom.children(of: id).compactMap({ indexByID[$0] })
        return StyleNode(
            identity: StyleIdentity(id: id, parent: parent, children: children),
            content: StyleContent(
                tag: element?.tag,
                attributes: element?.attributes ?? [:],
                text: node.text?.text
            ),
            state: StyleState(
                isFocused: node.isFocused,
                isFocusVisible: node.isFocusVisible,
                isHovered: node.isHovered,
                satisfiedHas: node.satisfiedHas
            )
        )
    }
}
