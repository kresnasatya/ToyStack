import Foundation

/// Lightweight view over one node in a `DOMTree`.
///
/// The view carries no node data; it resolves `id` against the tree on each
/// access. A1 uses `raw` to bridge call sites that still need the class type.
/// The tree reference is strong on purpose: a layout object that survives a
/// document swap must resolve against its own tree, not trap on a dead one.
@MainActor
struct DOMRef {
    let id: NodeID
    let dom: DOMTree
}

extension DOMRef {
    /// Temporary bridge to the class tree. Deleted in C3.
    var raw: any DOMNode {
        guard let node: any DOMNode = dom.node(id) else {
            preconditionFailure("DOMRef points at a missing node")
        }
        return node
    }

    var style: StyleFields { raw.style }

    var animations: [AnimationKey: Animation] {
        get { raw.animations }
        nonmutating set { raw.animations = newValue }
    }

    var isFocused: Bool { raw.isFocused }

    var isFocusVisible: Bool { raw.isFocusVisible }

    var inheritedStyleOwner: DOMRef {
        if raw is TextNode, let parent { return parent }
        return self
    }

    var layout: LayoutRef? {
        guard let tree: LayoutTree = dom.layoutTree,
            let id: LayoutID = tree.primaryLayout(for: id)
        else { return nil }
        return LayoutRef(id: id, tree: tree)
    }

    var parent: DOMRef? {
        guard let parent: any DOMNode = raw.parent else { return nil }
        return DOMRef(id: dom.id(of: parent), dom: dom)
    }

    var children: [DOMRef] {
        return raw.children.map { DOMRef(id: dom.id(of: $0), dom: dom) }
    }

    var element: ElementRef? {
        return raw is Element ? ElementRef(ref: self) : nil
    }

    var text: TextRef? {
        return raw is TextNode ? TextRef(ref: self) : nil
    }
}
