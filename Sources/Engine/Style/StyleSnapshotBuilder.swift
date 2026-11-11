import Foundation

// MARK: - StyleSnapshotBuilder

/// The only style-phase code that touches `DOMRef`.
@MainActor
enum StyleSnapshotBuilder {
    static func build(root: DOMRef) -> StyleSnapshot {
        return build(dom: root.dom)
    }

    /// Detached nodes have no parent and no children, which is what matching
    /// saw before the snapshot existed.
    static func build(dom: DOMTree) -> StyleSnapshot {
        var nodes: [StyleNode?] = []
        var indexByID: [NodeID: Int] = [:]
        dom.forEachNode { id in
            indexByID[id] = nodes.count
            nodes.append(nil)
        }
        dom.forEachNode { id in
            guard let index: Int = indexByID[id], dom.node(id) != nil else { return }
            let node: DOMRef = dom.ref(id)
            let element: ElementRef? = node.element
            let parent: Int? = dom.parent(of: id).flatMap({ indexByID[$0] })
            let children: [Int] = dom.children(of: id).compactMap({ indexByID[$0] })
            nodes[index] = StyleNode(
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
        let root: Int = indexByID[dom.root] ?? 0
        return StyleSnapshot(nodes: nodes, indexByID: indexByID, root: root)
    }
}
