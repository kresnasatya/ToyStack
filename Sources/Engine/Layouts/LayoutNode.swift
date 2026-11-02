import Foundation

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
    var fields: ArenaFieldStore
    var hasDirtyDescendants: Bool
}
