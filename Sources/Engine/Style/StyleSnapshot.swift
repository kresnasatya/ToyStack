import Foundation

// MARK: - StyleSnapshot

/// Frozen view of the DOM for selector matching.
///
/// Matching is a read: it looks at tags, attributes, state flags, and the
/// `:has` cache. Copying those into values lets the selectors run without a
/// `DOMTree`, and keeps the pass that mutates styles separate from the pass
/// that decides what matches.
struct StyleSnapshot {
    var nodes: [StyleNode?]
    var indexByID: [NodeID: Int]
    var root: Int

    func index(of id: NodeID) -> Int? {
        return indexByID[id]
    }

    func node(_ index: Int) -> StyleNode {
        guard let node: StyleNode = nodes[index] else {
            preconditionFailure("style snapshot index points at a hole")
        }
        return node
    }

    func parent(of index: Int) -> Int? {
        return node(index).identity.parent
    }

    func children(of index: Int) -> [Int] {
        return node(index).identity.children
    }

    func preorder(from index: Int, into order: inout [Int]) {
        order.append(index)
        for child in children(of: index) {
            preorder(from: child, into: &order)
        }
    }
}

// MARK: - StyleNode

struct StyleNode {
    var identity: StyleIdentity
    var content: StyleContent
    var state: StyleState
}

struct StyleIdentity {
    var id: NodeID
    var parent: Int?
    var children: [Int]
}

struct StyleContent {
    var tag: String?
    var attributes: [String: String]
    var text: String?
}

struct StyleState {
    var isFocused: Bool
    var isFocusVisible: Bool
    var isHovered: Bool
    var satisfiedHas: Set<Int>
}
