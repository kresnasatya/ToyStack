import CoreGraphics
import Foundation

// MARK: - LayoutRef

/// Lightweight view over one layout node in a `LayoutTree`.
///
/// Delegates to the tree's value accessors, so the same code keeps working
/// while call sites migrate to `tree.x(id)` and the ref is deleted.
@MainActor
struct LayoutRef {
    let id: LayoutID
    let tree: LayoutTree
}

extension LayoutRef {
    var node: DOMRef {
        return DOMRef(id: tree.domID(of: id), dom: tree.dom)
    }

    var parent: LayoutRef? {
        guard let parent: LayoutID = tree.parentID(of: id) else { return nil }
        return LayoutRef(id: parent, tree: tree)
    }

    var previous: LayoutRef? {
        get {
            guard let previous: LayoutID = tree.previousID(of: id) else { return nil }
            return LayoutRef(id: previous, tree: tree)
        }
        nonmutating set {
            tree.setPreviousField(newValue?.id, of: id)
        }
    }

    var children: [LayoutRef] {
        get {
            return tree.childrenIDs(of: id).map({ LayoutRef(id: $0, tree: tree) })
        }
        nonmutating set {
            tree.setChildrenField(newValue.map({ $0.id }), of: id)
        }
    }

    var kind: LayoutKind {
        return tree.kind(id)
    }

    var domNode: NodeID {
        return tree.domID(of: id)
    }

    var hasDirtyDescendants: Bool {
        get { tree.hasDirtyDescendants(at: id) }
        nonmutating set { tree.setDirtyDescendants(newValue, at: id) }
    }

    // MARK: - Typed payloads

    var documentData: DocumentData {
        get { tree.documentData(id) }
        nonmutating set { tree.setKind(.document(newValue), at: id) }
    }

    var blockData: BlockData {
        get { tree.blockData(id) }
        nonmutating set { tree.setKind(.block(newValue), at: id) }
    }

    var lineData: LineData {
        get { tree.lineData(id) }
        nonmutating set { tree.setKind(.line(newValue), at: id) }
    }

    var textData: TextData {
        get { tree.textData(id) }
        nonmutating set { tree.setKind(.text(newValue), at: id) }
    }

    var embedData: EmbedData {
        get { tree.embedData(id) }
        nonmutating set { tree.setKind(.embed(newValue), at: id) }
    }

    var isBlock: Bool { return tree.isBlock(id) }
    var isLine: Bool { return tree.isLine(id) }
    var isText: Bool { return tree.isText(id) }
    var isEmbed: Bool { return tree.isEmbed(id) }
    var isDocument: Bool { return tree.isDocument(id) }
    var isIframe: Bool { return tree.isIframe(id) }

    // MARK: - Geometry

    var x: CGFloat {
        get { tree.x(id) }
        nonmutating set { tree.setField(.x, newValue, for: id) }
    }

    var y: CGFloat {
        get { tree.y(id) }
        nonmutating set { tree.setField(.y, newValue, for: id) }
    }

    var width: CGFloat {
        get { tree.width(id) }
        nonmutating set { tree.setField(.width, newValue, for: id) }
    }

    var height: CGFloat {
        get { tree.height(id) }
        nonmutating set { tree.setField(.height, newValue, for: id) }
    }

    var heightIfUsed: CGFloat? {
        return tree.heightIfUsed(at: id)
    }

    var zoom: CGFloat {
        get { tree.zoom(id) }
        nonmutating set { tree.setField(.zoom, newValue, for: id) }
    }

    var font: BrowserFont {
        get { tree.font(id) }
        nonmutating set { tree.setFont(newValue, for: id) }
    }

    var ascent: CGFloat {
        get { tree.ascent(id) }
        nonmutating set { tree.setField(.ascent, newValue, for: id) }
    }

    var descent: CGFloat {
        get { tree.descent(id) }
        nonmutating set { tree.setField(.descent, newValue, for: id) }
    }

    var inlineContent: UInt64 {
        get { tree.inlineContent(id) }
        nonmutating set { tree.setInlineContent(newValue, for: id) }
    }

    func selfRect() -> Rect {
        return tree.selfRect(id)
    }

    // MARK: - Actions

    func markAncestorsDirty() {
        tree.markAncestorsDirty(from: id)
    }

    func layoutNeeded() -> Bool {
        return tree.layoutNeeded(id)
    }

    func layout() {
        switch kind {
        case .document:
            break
        case .block:
            tree.layoutBlock(self)
        case .line:
            tree.layoutLine(self)
        case .text:
            tree.layoutText(self)
        case .embed:
            tree.layoutEmbed(self)
        }
    }
}
