import Foundation

// MARK: - LayoutNode

struct LayoutNodeSeed {
    let kind: LayoutKind
    let dom: NodeID
    let links: LayoutLinks
    let state: LayoutState
}

// MARK: - LayoutNode

struct LayoutNode {
    var kind: LayoutKind
    var dom: NodeID
    var links: LayoutLinks
    var state: LayoutState
}

extension LayoutNode {
    static func removed(dom: NodeID) -> LayoutNode {
        return LayoutNode(
            kind: .document(DocumentData(pageZoom: 1)),
            dom: dom,
            links: LayoutLinks(
                parent: nil,
                previous: nil,
                children: [],
                versions: LinkVersions(children: 0, previous: 0)
            ),
            state: LayoutState(
                fields: LayoutFieldStore(),
                hasDirtyDescendants: false,
                isRemoved: true
            )
        )
    }
}

// MARK: - LayoutLinks

struct LayoutLinks {
    var parent: LayoutID?
    var previous: LayoutID?
    var children: [LayoutID]
    var versions: LinkVersions
}

// MARK: - LinkVersions

struct LinkVersions {
    var children: UInt64
    var previous: UInt64
}

// MARK: - LayoutState

struct LayoutState {
    var fields: LayoutFieldStore
    var hasDirtyDescendants: Bool
    var isRemoved: Bool
}
