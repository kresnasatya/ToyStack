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
            tree.setPreviousField(newValue?.id, of: id)
        }
    }

    var children: [LayoutRef] {
        get {
            return tree.node(id).links.children.map({ LayoutRef(id: $0, tree: tree) })
        }
        nonmutating set {
            tree.setChildrenField(newValue.map({ $0.id }), of: id)
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
        get { readCGFloat(.x) }
        nonmutating set { tree.setField(.x, newValue, for: id) }
    }

    var y: CGFloat {
        get { readCGFloat(.y) }
        nonmutating set { tree.setField(.y, newValue, for: id) }
    }

    var width: CGFloat {
        get { readCGFloat(.width) }
        nonmutating set { tree.setField(.width, newValue, for: id) }
    }

    var height: CGFloat {
        get { readCGFloat(.height) }
        nonmutating set { tree.setField(.height, newValue, for: id) }
    }

    var heightIfUsed: CGFloat? {
        guard tree.isUsed(.height, at: id) else { return nil }
        return tree.storedCGFloat(.height, at: id)
    }

    var zoom: CGFloat {
        get { readCGFloat(.zoom) }
        nonmutating set { tree.setField(.zoom, newValue, for: id) }
    }

    var font: BrowserFont {
        get {
            if tree.isDirty(.font, at: id) {
                assertionFailure("Read dirty field \(kind).font")
            }
            guard tree.isUsed(.font, at: id) else {
                fatalError("Read unset field \(kind).font")
            }
            return tree.storedFont(id)
        }
        nonmutating set { tree.setFont(newValue, for: id) }
    }

    var ascent: CGFloat {
        get { readCGFloat(.ascent) }
        nonmutating set { tree.setField(.ascent, newValue, for: id) }
    }

    var descent: CGFloat {
        get { readCGFloat(.descent) }
        nonmutating set { tree.setField(.descent, newValue, for: id) }
    }

    var inlineContent: UInt64 {
        get {
            if tree.isDirty(.inlineContent, at: id) {
                assertionFailure("Read dirty field \(kind).inlineContent")
            }
            guard tree.isUsed(.inlineContent, at: id) else {
                fatalError("Read unset field \(kind).inlineContent")
            }
            return tree.storedInlineContent(id)
        }
        nonmutating set { tree.setInlineContent(newValue, for: id) }
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

    // MARK: - Actions

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

    // MARK: - Field reads

    private func readCGFloat(_ field: LayoutField) -> CGFloat {
        if tree.isDirty(field, at: id) {
            assertionFailure("Read dirty field \(kind).\(field.rawValue)")
        }
        guard tree.isUsed(field, at: id) else {
            fatalError("Read unset field \(kind).\(field.rawValue)")
        }
        return tree.storedCGFloat(field, at: id)
    }
}
