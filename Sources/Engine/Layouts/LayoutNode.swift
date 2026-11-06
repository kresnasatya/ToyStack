import Foundation

// MARK: - LayoutNode

/// The pieces needed to insert a prepared node into the tree.
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
}
