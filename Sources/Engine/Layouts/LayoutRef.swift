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

    var previous: LayoutRef? {
        get {
            guard let previous: LayoutID = tree.node(id).links.previous else { return nil }
            return LayoutRef(id: previous, tree: tree)
        }
        nonmutating set {
            tree.setPrevious(newValue?.id, of: id)
        }
    }

    var children: [LayoutRef] {
        get {
            return tree.node(id).links.children.map({ LayoutRef(id: $0, tree: tree) })
        }
        nonmutating set {
            childrenField.set(newValue.map({ $0.id }))
        }
    }

    var kind: LayoutKind {
        return tree.node(id).kind
    }

    var domNode: NodeID {
        return tree.node(id).dom
    }

    var hasDirtyDescendants: Bool {
        get { tree.node(id).state.hasDirtyDescendants }
        nonmutating set { tree.setDirtyDescendants(newValue, at: id) }
    }

    // MARK: - Typed payloads

    var documentData: DocumentData {
        get {
            guard case .document(let data) = kind else {
                preconditionFailure("Not a document node")
            }
            return data
        }
        nonmutating set {
            tree.setKind(.document(newValue), at: id)
        }
    }

    var blockData: BlockData {
        get {
            guard case .block(let data) = kind else {
                preconditionFailure("Not a block node")
            }
            return data
        }
        nonmutating set {
            tree.setKind(.block(newValue), at: id)
        }
    }

    var lineData: LineData {
        get {
            guard case .line(let data) = kind else {
                preconditionFailure("Not a line node")
            }
            return data
        }
        nonmutating set {
            tree.setKind(.line(newValue), at: id)
        }
    }

    var textData: TextData {
        get {
            guard case .text(let data) = kind else {
                preconditionFailure("Not a text node")
            }
            return data
        }
        nonmutating set {
            tree.setKind(.text(newValue), at: id)
        }
    }

    var embedData: EmbedData {
        get {
            guard case .embed(let data) = kind else {
                preconditionFailure("Not an embed node")
            }
            return data
        }
        nonmutating set {
            tree.setKind(.embed(newValue), at: id)
        }
    }

    var isBlock: Bool { if case .block = kind { return true }; return false }
    var isLine: Bool { if case .line = kind { return true }; return false }
    var isText: Bool { if case .text = kind { return true }; return false }
    var isEmbed: Bool { if case .embed = kind { return true }; return false }
    var isDocument: Bool { if case .document = kind { return true }; return false }
    var isIframe: Bool { if case .embed(.iframe) = kind { return true }; return false }

    // MARK: - Geometry

    var x: CGFloat {
        get { xField.get() }
        nonmutating set { xField.set(newValue) }
    }

    var y: CGFloat {
        get { yField.get() }
        nonmutating set { yField.set(newValue) }
    }

    var width: CGFloat {
        get { widthField.get() }
        nonmutating set { widthField.set(newValue) }
    }

    var height: CGFloat {
        get { heightField.get() }
        nonmutating set { heightField.set(newValue) }
    }

    var zoom: CGFloat {
        get { zoomField.get() }
        nonmutating set { zoomField.set(newValue) }
    }

    var font: BrowserFont {
        get { fontField.get() }
        nonmutating set { fontField.set(newValue) }
    }

    var ascent: CGFloat {
        get { ascentField.get() }
        nonmutating set { ascentField.set(newValue) }
    }

    var descent: CGFloat {
        get { descentField.get() }
        nonmutating set { descentField.set(newValue) }
    }

    func selfRect() -> Rect {
        switch kind {
        case .block:
            return tree.blockSelfRect(self)
        case .text:
            return tree.textSelfRect(self)
        default:
            return Rect(left: x, top: y, right: x + width, bottom: y + height)
        }
    }

    // MARK: - Field handles

    var xField: LayoutFieldHandle<CGFloatFieldAccess> { layoutField(.x) }
    var yField: LayoutFieldHandle<CGFloatFieldAccess> { layoutField(.y) }
    var widthField: LayoutFieldHandle<CGFloatFieldAccess> { layoutField(.width) }
    var heightField: LayoutFieldHandle<CGFloatFieldAccess> { layoutField(.height) }
    var zoomField: LayoutFieldHandle<CGFloatFieldAccess> { layoutField(.zoom) }
    var ascentField: LayoutFieldHandle<CGFloatFieldAccess> { layoutField(.ascent) }
    var descentField: LayoutFieldHandle<CGFloatFieldAccess> { layoutField(.descent) }
    var fontField: LayoutFieldHandle<FontFieldAccess> { layoutField(.font) }
    var childrenField: LayoutFieldHandle<ChildrenFieldAccess> { layoutField(.children) }
    var previousField: LayoutFieldHandle<PreviousFieldAccess> { layoutField(.previous) }
    var inlineContentField: LayoutFieldHandle<InlineContentFieldAccess> { layoutField(.inlineContent) }

    func layoutField<Access: LayoutFieldAccess>(_ field: LayoutField) -> LayoutFieldHandle<Access> {
        return LayoutFieldHandle(owner: self, field: field)
    }

    func markAncestorsDirty() {
        tree.markAncestorsDirty(from: id)
    }

    func layoutNeeded() -> Bool {
        switch kind {
        case .document:
            return tree.documentLayoutNeeded(self)
        case .block:
            return tree.blockLayoutNeeded(self)
        case .line:
            return tree.lineLayoutNeeded(self)
        case .text:
            return tree.textLayoutNeeded(self)
        case .embed:
            return tree.embedLayoutNeeded(self)
        }
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

    func fieldRef(_ field: LayoutField) -> FieldRef {
        let tree: LayoutTree = self.tree
        let id: LayoutID = self.id
        return FieldRef(
            key: .layout(id, field),
            markBody: { [weak tree] in
                tree?.markField(field, at: id)
            },
            isAlive: { [weak tree] in
                tree?.contains(id) ?? false
            }
        )
    }
}
