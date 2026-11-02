import CoreGraphics
import Foundation

// MARK: - LayoutRef

/// Lightweight view over one layout node in a `LayoutTree`.
@MainActor
struct LayoutRef {
    let id: LayoutID
    let tree: LayoutTree
}

extension LayoutRef {
    var node: DOMRef {
        return DOMRef(id: tree.node(id).dom, dom: tree.dom)
    }

    var parent: LayoutRef? {
        guard let parent: LayoutID = tree.node(id).links.parent else { return nil }
        return LayoutRef(id: parent, tree: tree)
    }

    var children: [LayoutRef] {
        return tree.node(id).links.children.map({ LayoutRef(id: $0, tree: tree) })
    }

    var kind: LayoutKind {
        return tree.node(id).kind
    }

    var x: CGFloat {
        get { tree.node(id).state.fields.geometry.origin.x }
        set { tree.setField(.x, newValue, for: id) }
    }

    var y: CGFloat {
        get { tree.node(id).state.fields.geometry.origin.y }
        set { tree.setField(.y, newValue, for: id) }
    }

    var width: CGFloat {
        get { tree.node(id).state.fields.geometry.size.width }
        set { tree.setField(.width, newValue, for: id) }
    }

    var height: CGFloat {
        get { tree.node(id).state.fields.geometry.size.height }
        set { tree.setField(.height, newValue, for: id) }
    }

    var zoom: CGFloat {
        get { tree.node(id).state.fields.geometry.zoom }
        set { tree.setField(.zoom, newValue, for: id) }
    }

    var font: BrowserFont {
        get { tree.node(id).state.fields.inlineText.font }
        set { tree.setFont(newValue, for: id) }
    }

    func selfRect() -> Rect {
        return Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
