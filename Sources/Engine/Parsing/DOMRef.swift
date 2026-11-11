import Foundation

/// The tree reference is strong on purpose: a layout object that survives a
/// document swap must resolve against its own tree, not trap on a dead one.
@MainActor
struct DOMRef {
    let id: NodeID
    let dom: DOMTree
}

extension DOMRef {
    var node: DOMNode? { dom.node(id) }

    var style: StyleFields { dom.style(of: id) }

    var animations: [AnimationKey: Animation] {
        get { dom.animations(of: id) }
        nonmutating set { dom.setAnimations(newValue, of: id) }
    }

    var isFocused: Bool { dom.flags(of: id).isFocused }

    var isFocusVisible: Bool { dom.flags(of: id).isFocusVisible }

    var isHovered: Bool { dom.flags(of: id).isHovered }

    var satisfiedHas: Set<Int> {
        get { dom.flags(of: id).satisfiedHas }
        nonmutating set { dom.setSatisfiedHas(newValue, of: id) }
    }

    var inheritedStyleOwner: DOMRef {
        if dom.isText(id), let parent { return parent }
        return self
    }

    var layoutID: LayoutID? {
        return dom.layoutBox?.tree.primaryLayout(for: id)
    }

    var parent: DOMRef? {
        guard let parent: NodeID = dom.parent(of: id) else { return nil }
        return DOMRef(id: parent, dom: dom)
    }

    var children: [DOMRef] {
        return dom.children(of: id).map({ DOMRef(id: $0, dom: dom) })
    }

    var element: ElementRef? {
        return dom.isElement(id) ? ElementRef(ref: self) : nil
    }

    var text: TextRef? {
        return dom.isText(id) ? TextRef(ref: self) : nil
    }

    func isInclusiveAncestor(of other: DOMRef) -> Bool {
        return dom.isInclusiveAncestor(id, of: other.id)
    }

    var description: String {
        if let element: ElementData = dom.element(id) {
            return "<\(element.tag)>"
        }
        if let text: DOMTextData = dom.text(id) {
            return "\"\(text.text)\""
        }
        return "<missing>"
    }
}
