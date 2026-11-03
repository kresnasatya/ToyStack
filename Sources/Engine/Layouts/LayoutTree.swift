import CoreGraphics
import Foundation

// MARK: - LayoutTree

/// Arena of layout nodes. One tree belongs to one document (`DOMTree`).
///
/// Nodes are append-only: removing a subtree writes `nil` into the hole and
/// never reuses the ID, so a stale `LayoutID` cannot point at another node.
struct LayoutTree {
    private(set) var nodes: [LayoutNode?]
    private(set) var primaryByNode: [NodeID: LayoutID]
    var dependencies: DependencyIndex
    private var source: LayoutTreeSource

    private var storageEffects: [LayoutEffect] {
        get { source.effects }
        set { source.effects = newValue }
    }

    var dom: DOMTree { return source.dom }
    var inputs: LayoutInputs { return source.inputs }

    func domView(_ id: LayoutID) -> LayoutDOMView {
        return LayoutDOMView(inputs: inputs, id: domID(of: id))
    }

    func domView(_ node: NodeID) -> LayoutDOMView {
        return LayoutDOMView(inputs: inputs, id: node)
    }

    func fontFor(_ dom: NodeID, zoom: CGFloat) -> BrowserFont {
        let style: TextStyle.Font = inputs.font(dom)
        return getFont(
            size: Int(style.size * zoom),
            weight: style.weight.cssValue,
            style: style.style.browserFontStyle,
            family: style.family
        )
    }

    func fontFor(_ id: LayoutID, zoom: CGFloat) -> BrowserFont {
        return fontFor(domID(of: id), zoom: zoom)
    }

    mutating func refreshInputs(_ inputs: LayoutInputs) {
        source.inputs = inputs
    }

    mutating func noteStyleChange(_ node: NodeID, _ property: StyleProperty) {
        source.inputs.styleChanges[node, default: []].insert(property)
    }

    mutating func note(_ effect: LayoutEffect) {
        storageEffects.append(effect)
    }

    mutating func takeEffects() -> [LayoutEffect] {
        let effects: [LayoutEffect] = storageEffects
        storageEffects.removeAll(keepingCapacity: true)
        return effects
    }

    init(dom: DOMTree, root: NodeID, inputs: LayoutInputs) {
        self.nodes = []
        self.primaryByNode = [:]
        self.dependencies = DependencyIndex()
        self.source = LayoutTreeSource(inputs: inputs, dom: dom)
        self.nodes.reserveCapacity(1024)
        let document: LayoutID = append(
            kind: .document(DocumentData(pageZoom: 1)),
            dom: root,
            parent: nil,
            previous: nil
        )
        assert(document.raw == 0)
        primaryByNode[root] = document
        for field in [LayoutField.zoom, .width, .x, .y, .children] {
            markUsed(field, at: document)
        }
    }

    @MainActor
    init(dom: DOMTree) {
        self.init(
            dom: dom,
            root: dom.root,
            inputs: LayoutInputsBuilder.build(dom: dom)
        )
    }

    // MARK: - Identity

    mutating func append(
        kind: LayoutKind,
        dom: NodeID,
        parent: LayoutID?,
        previous: LayoutID?
    ) -> LayoutID {
        let id: LayoutID = LayoutID(raw: nodes.count)
        let links: LayoutLinks = LayoutLinks(
            parent: parent,
            previous: previous,
            children: [],
            versions: LinkVersions(children: 0, previous: 0)
        )
        let state: LayoutState = LayoutState(
            fields: LayoutFieldStore(),
            hasDirtyDescendants: false
        )
        nodes.append(LayoutNode(kind: kind, dom: dom, links: links, state: state))
        return id
    }

    mutating func setPrimary(_ id: LayoutID, for node: NodeID) {
        primaryByNode[node] = id
    }

    func primaryLayout(for node: NodeID) -> LayoutID? {
        return primaryByNode[node]
    }

    var rootID: LayoutID {
        return LayoutID(raw: 0)
    }

    mutating func markDocumentWidthDirty() {
        markField(.width, at: rootID)
    }

    mutating func markDocumentGeometryDirty() {
        markField(.width, at: rootID)
        markField(.zoom, at: rootID)
    }

    func documentNeedsLayout() -> Bool {
        return documentLayoutNeeded(rootID)
    }

    var liveIDs: [LayoutID] {
        var ids: [LayoutID] = []
        ids.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() where node != nil {
            ids.append(LayoutID(raw: index))
        }
        return ids
    }

    func node(_ id: LayoutID) -> LayoutNode {
        guard let node: LayoutNode = nodes[id.raw] else {
            preconditionFailure("LayoutID points at a removed node")
        }
        return node
    }

    func kind(_ id: LayoutID) -> LayoutKind {
        return node(id).kind
    }

    func contains(_ id: LayoutID) -> Bool {
        guard id.raw >= 0, id.raw < nodes.count else { return false }
        return nodes[id.raw] != nil
    }

    mutating func setKind(_ kind: LayoutKind, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.kind = kind
        nodes[id.raw] = node
    }

    // MARK: - Links

    func children(of id: LayoutID) -> [LayoutID] {
        return node(id).links.children
    }

    mutating func setChildren(_ children: [LayoutID], of id: LayoutID) {
        var parent: LayoutNode = node(id)
        parent.links.children = children
        parent.links.versions.children += 1
        nodes[id.raw] = parent
        for child in children {
            var node: LayoutNode = self.node(child)
            node.links.parent = id
            nodes[child.raw] = node
        }
    }

    mutating func setPrevious(_ previous: LayoutID?, of id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.links.previous = previous
        node.links.versions.previous += 1
        nodes[id.raw] = node
    }

    mutating func removeSubtree(_ id: LayoutID) {
        guard nodes[id.raw] != nil else { return }
        let links: LayoutLinks = node(id).links
        let parent: LayoutID? = links.parent
        if let parent {
            var node: LayoutNode = self.node(parent)
            node.links.children.removeAll(where: { $0 == id })
            node.links.versions.children += 1
            nodes[parent.raw] = node
        }
        var removed: [LayoutID] = []
        collectSubtreeIDs(id, into: &removed)
        removeRecursively(id)
        if let parent {
            reindexDependencies(parent)
        }
        for removedID in removed {
            dependencies.removeLayoutEdges(for: removedID)
        }
    }

    private func collectSubtreeIDs(_ id: LayoutID, into ids: inout [LayoutID]) {
        guard let node: LayoutNode = nodes[id.raw] else { return }
        ids.append(id)
        for child in node.links.children {
            collectSubtreeIDs(child, into: &ids)
        }
    }

    mutating private func removeRecursively(_ id: LayoutID) {
        guard let node: LayoutNode = nodes[id.raw] else { return }
        for child in node.links.children {
            removeRecursively(child)
        }
        if let primary: LayoutID = primaryByNode[node.dom], primary == id {
            primaryByNode.removeValue(forKey: node.dom)
        }
        nodes[id.raw] = nil
    }

    /// Frees nodes that are no longer reachable from the document root.
    /// Returns the dropped IDs, so callers can invalidate caches that may
    /// still hold them.
    @discardableResult
    mutating func sweepUnreachable() -> Set<LayoutID> {
        var reachable: Set<LayoutID> = []
        collectReachable(rootID, into: &reachable)
        var removed: Set<LayoutID> = []
        for index in nodes.indices {
            guard let node: LayoutNode = nodes[index] else { continue }
            let id: LayoutID = LayoutID(raw: index)
            if reachable.contains(id) { continue }
            if let primary: LayoutID = primaryByNode[node.dom], primary == id {
                primaryByNode.removeValue(forKey: node.dom)
            }
            nodes[index] = nil
            removed.insert(id)
        }
        if !removed.isEmpty {
            for removedID in removed {
                dependencies.removeLayoutEdges(for: removedID)
            }
        }
        return removed
    }

    private func collectReachable(_ id: LayoutID, into reachable: inout Set<LayoutID>) {
        guard nodes[id.raw] != nil, !reachable.contains(id) else { return }
        reachable.insert(id)
        for child in node(id).links.children {
            collectReachable(child, into: &reachable)
        }
    }

    // MARK: - Style changes

    mutating func consumeStyleChanges() {
        var changed: [NodeID] = []
        for index in inputs.nodes.indices where inputs.nodes[index] != nil {
            let node: NodeID = NodeID(raw: UInt32(index))
            if !inputs.styleChanges(node).isEmpty {
                changed.append(node)
            }
        }

        var affected: Set<LayoutID> = []
        for node in changed {
            for property in inputs.styleChanges(node) {
                for dependent in dependencies.fields(for: .style(node, property)) {
                    guard case .layout(let id, _) = dependent else { continue }
                    affected.insert(id)
                }
            }
        }

        for id in affected {
            reindexDependencies(id)
        }

        for node in changed {
            for property in inputs.styleChanges(node) {
                markDependents(of: .style(node, property))
            }
        }
    }

    /// Marks the layout fields that read one DOM node's changed style properties.
    mutating func consumeStyleChanges(for node: NodeID) {
        for property in inputs.styleChanges(node) {
            markDependents(of: .style(node, property))
        }
    }

    // MARK: - Fields
    func isDirty(_ field: LayoutField, at id: LayoutID) -> Bool {
        return node(id).state.fields.isDirty(field)
    }

    func isUsed(_ field: LayoutField, at id: LayoutID) -> Bool {
        return node(id).state.fields.isUsed(field)
    }

    mutating func markUsed(_ field: LayoutField, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        let wasUsed: Bool = node.state.fields.isUsed(field)
        node.state.fields.markUsed(field)
        nodes[id.raw] = node
        guard !wasUsed else { return }
        let dependent: FieldKey = .layout(id, field)
        for input in LayoutInputTable.inputs(for: id, field: field, in: self) {
            dependencies.add(dependent, for: input)
        }
    }

    mutating func reindexDependencies(_ id: LayoutID) {
        var inputs: [LayoutField: [FieldKey]] = [:]
        for field in LayoutField.allCases where isUsed(field, at: id) {
            inputs[field] = LayoutInputTable.inputs(for: id, field: field, in: self)
        }
        dependencies.reindex(id, inputs: inputs)
    }

    mutating func markClean(_ field: LayoutField, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.markClean(field)
        nodes[id.raw] = node
    }

    mutating func markField(_ field: LayoutField, at id: LayoutID) {
        guard !isDirty(field, at: id) else { return }
        profiler.count("layout.field.mark")
        var node: LayoutNode = self.node(id)
        node.state.fields.markDirty(field)
        nodes[id.raw] = node
        markAncestorsDirty(from: id)
    }

    mutating func markAncestorsDirty(from id: LayoutID) {
        var current: LayoutID? = node(id).links.parent
        while let ancestor = current, !node(ancestor).state.hasDirtyDescendants {
            var node: LayoutNode = self.node(ancestor)
            node.state.hasDirtyDescendants = true
            nodes[ancestor.raw] = node
            current = node.links.parent
        }
    }

    mutating func setDirtyDescendants(_ value: Bool, at id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.hasDirtyDescendants = value
        nodes[id.raw] = node
    }

    // MARK: - Values

    func storedCGFloat(_ field: LayoutField, at id: LayoutID) -> CGFloat {
        let fields: LayoutFieldStore = node(id).state.fields
        switch field {
        case .x:
            return fields.geometry.origin.x
        case .y:
            return fields.geometry.origin.y
        case .width:
            return fields.geometry.size.width
        case .height:
            return fields.geometry.size.height
        case .zoom:
            return fields.geometry.zoom
        case .ascent:
            return fields.inlineText.ascent
        case .descent:
            return fields.inlineText.descent
        default:
            preconditionFailure("Field \(field.rawValue) is not a CGFloat value")
        }
    }

    func storedFont(_ id: LayoutID) -> BrowserFont {
        return node(id).state.fields.inlineText.font
    }

    func storedInlineContent(_ id: LayoutID) -> UInt64 {
        return node(id).state.fields.inlineText.inlineContent
    }

    mutating private func writeCGFloat(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        var node: LayoutNode = self.node(id)
        switch field {
        case .x:
            node.state.fields.geometry.origin.x = value
        case .y:
            node.state.fields.geometry.origin.y = value
        case .width:
            node.state.fields.geometry.size.width = value
        case .height:
            node.state.fields.geometry.size.height = value
        case .zoom:
            node.state.fields.geometry.zoom = value
        case .ascent:
            node.state.fields.inlineText.ascent = value
        case .descent:
            node.state.fields.inlineText.descent = value
        default:
            preconditionFailure("Field \(field.rawValue) is not a CGFloat value")
        }
        nodes[id.raw] = node
    }

    mutating private func writeFont(_ font: BrowserFont, for id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.inlineText.font = font
        nodes[id.raw] = node
    }

    mutating private func writeInlineContent(_ value: UInt64, for id: LayoutID) {
        var node: LayoutNode = self.node(id)
        node.state.fields.inlineText.inlineContent = value
        nodes[id.raw] = node
    }

    /// Writes a computed value and dirties the fields that read it.
    mutating func setField(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        let wasUsed: Bool = isUsed(field, at: id)
        let changed: Bool = !wasUsed || storedCGFloat(field, at: id) != value
        writeCGFloat(field, value, for: id)
        markUsed(field, at: id)
        markClean(field, at: id)
        guard changed else { return }
        profiler.count("layout.field.set")
        markDependents(of: .layout(id, field))
    }

    /// Writes a value without counting it as a computed change.
    mutating func setFieldClean(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        writeCGFloat(field, value, for: id)
        markUsed(field, at: id)
        markClean(field, at: id)
    }

    mutating func setFont(_ font: BrowserFont, for id: LayoutID) {
        let wasUsed: Bool = isUsed(.font, at: id)
        let changed: Bool = !wasUsed || !CFEqual(storedFont(id).ctFont, font.ctFont)
        writeFont(font, for: id)
        markUsed(.font, at: id)
        markClean(.font, at: id)
        guard changed else { return }
        profiler.count("layout.field.set")
        markDependents(of: .layout(id, .font))
    }

    mutating func setFontClean(_ font: BrowserFont, for id: LayoutID) {
        writeFont(font, for: id)
        markUsed(.font, at: id)
        markClean(.font, at: id)
    }

    mutating func setInlineContent(_ value: UInt64, for id: LayoutID) {
        let wasUsed: Bool = isUsed(.inlineContent, at: id)
        let changed: Bool = !wasUsed || storedInlineContent(id) != value
        writeInlineContent(value, for: id)
        markUsed(.inlineContent, at: id)
        markClean(.inlineContent, at: id)
        guard changed else { return }
        profiler.count("layout.field.set")
        markDependents(of: .layout(id, .inlineContent))
    }

    mutating func setInlineContentClean(_ value: UInt64, for id: LayoutID) {
        writeInlineContent(value, for: id)
        markUsed(.inlineContent, at: id)
        markClean(.inlineContent, at: id)
    }

    mutating func setChildrenField(_ children: [LayoutID], of id: LayoutID) {
        let wasUsed: Bool = isUsed(.children, at: id)
        let changed: Bool = !wasUsed || self.children(of: id) != children
        let reparented: [LayoutID] = children.filter({ node($0).links.parent != id })
        markUsed(.children, at: id)
        setChildren(children, of: id)
        markClean(.children, at: id)
        if changed || !reparented.isEmpty {
            reindexDependencies(id)
            for child in reparented {
                reindexDependencies(child)
            }
        }
        if changed {
            profiler.count("layout.field.set")
            markDependents(of: .layout(id, .children))
        }
    }

    mutating func setChildrenClean(_ children: [LayoutID], of id: LayoutID) {
        setChildren(children, of: id)
        markUsed(.children, at: id)
        markClean(.children, at: id)
    }

    mutating func setPreviousField(_ previous: LayoutID?, of id: LayoutID) {
        let wasUsed: Bool = isUsed(.previous, at: id)
        let changed: Bool = !wasUsed || node(id).links.previous != previous
        markUsed(.previous, at: id)
        setPrevious(previous, of: id)
        markClean(.previous, at: id)
        guard changed else { return }
        reindexDependencies(id)
        profiler.count("layout.field.set")
        markDependents(of: .layout(id, .previous))
    }

    mutating func setPreviousClean(_ previous: LayoutID?, of id: LayoutID) {
        setPrevious(previous, of: id)
        markUsed(.previous, at: id)
        markClean(.previous, at: id)
    }
}

// MARK: - Node accessors

/// Value API for one layout node, keyed by id.
extension LayoutTree {
    mutating func markDependents(of key: FieldKey) {
        for dependent in dependencies.fields(for: key) {
            guard case .layout(let id, let field) = dependent else { continue }
            markField(field, at: id)
        }
    }

    @MainActor
    func domRef(_ id: LayoutID) -> DOMRef {
        return DOMRef(id: domID(of: id), dom: dom)
    }

    func absoluteBounds(_ id: LayoutID) -> Rect {
        var rect: Rect = selfRect(id)
        var current: NodeID? = domID(of: id)
        while let node = current {
            if let t: CGPoint = inputs.style(node).visual.effects.translation {
                rect = Rect(
                    left: rect.left + t.x,
                    top: rect.top + t.y,
                    right: rect.right + t.x,
                    bottom: rect.bottom + t.y
                )
            }
            current = inputs.parent(node)
        }
        return rect
    }

    func pageZoom(_ id: LayoutID) -> CGFloat {
        if let parent: LayoutID = parentID(of: id) {
            return pageZoom(parent)
        }
        return kind(id).documentPageZoom
    }

    func resolvedZoom(_ id: LayoutID) -> CGFloat {
        let parentZoom: CGFloat = parentID(of: id).map({ zoom($0) }) ?? 1.0
        guard let factor: CGFloat = inputs.style(domID(of: id)).box.zoom else {
            return parentZoom
        }
        return parentZoom * factor
    }

    func readCGFloat(_ field: LayoutField, at id: LayoutID) -> CGFloat {
        if isDirty(field, at: id) {
            assertionFailure("Read dirty field \(kind(id)).\(field.rawValue)")
        }
        guard isUsed(field, at: id) else {
            fatalError("Read unset field \(kind(id)).\(field.rawValue)")
        }
        return storedCGFloat(field, at: id)
    }

    func x(_ id: LayoutID) -> CGFloat { return readCGFloat(.x, at: id) }
    func y(_ id: LayoutID) -> CGFloat { return readCGFloat(.y, at: id) }
    func width(_ id: LayoutID) -> CGFloat { return readCGFloat(.width, at: id) }
    func height(_ id: LayoutID) -> CGFloat { return readCGFloat(.height, at: id) }
    func zoom(_ id: LayoutID) -> CGFloat { return readCGFloat(.zoom, at: id) }
    func ascent(_ id: LayoutID) -> CGFloat { return readCGFloat(.ascent, at: id) }
    func descent(_ id: LayoutID) -> CGFloat { return readCGFloat(.descent, at: id) }

    func heightIfUsed(at id: LayoutID) -> CGFloat? {
        guard isUsed(.height, at: id) else { return nil }
        return storedCGFloat(.height, at: id)
    }

    func font(_ id: LayoutID) -> BrowserFont {
        if isDirty(.font, at: id) {
            assertionFailure("Read dirty field \(kind(id)).font")
        }
        guard isUsed(.font, at: id) else {
            fatalError("Read unset field \(kind(id)).font")
        }
        return storedFont(id)
    }

    func inlineContent(_ id: LayoutID) -> UInt64 {
        if isDirty(.inlineContent, at: id) {
            assertionFailure("Read dirty field \(kind(id)).inlineContent")
        }
        guard isUsed(.inlineContent, at: id) else {
            fatalError("Read unset field \(kind(id)).inlineContent")
        }
        return storedInlineContent(id)
    }

    // MARK: Payloads

    func documentData(_ id: LayoutID) -> DocumentData {
        guard case .document(let data) = kind(id) else {
            preconditionFailure("Not a document node")
        }
        return data
    }

    func blockData(_ id: LayoutID) -> BlockData {
        guard case .block(let data) = kind(id) else {
            preconditionFailure("Not a block node")
        }
        return data
    }

    func lineData(_ id: LayoutID) -> LineData {
        guard case .line(let data) = kind(id) else {
            preconditionFailure("Not a line node")
        }
        return data
    }

    func textData(_ id: LayoutID) -> TextData {
        guard case .text(let data) = kind(id) else {
            preconditionFailure("Not a text node")
        }
        return data
    }

    func embedData(_ id: LayoutID) -> EmbedData {
        guard case .embed(let data) = kind(id) else {
            preconditionFailure("Not an embed node")
        }
        return data
    }

    // MARK: Structure

    func domID(of id: LayoutID) -> NodeID { return node(id).dom }
    func parentID(of id: LayoutID) -> LayoutID? { return node(id).links.parent }
    func previousID(of id: LayoutID) -> LayoutID? { return node(id).links.previous }
    func childrenIDs(of id: LayoutID) -> [LayoutID] { return node(id).links.children }
    func hasDirtyDescendants(at id: LayoutID) -> Bool { return node(id).state.hasDirtyDescendants }

    func isBlock(_ id: LayoutID) -> Bool { if case .block = kind(id) { return true }; return false }
    func isLine(_ id: LayoutID) -> Bool { if case .line = kind(id) { return true }; return false }
    func isText(_ id: LayoutID) -> Bool { if case .text = kind(id) { return true }; return false }
    func isEmbed(_ id: LayoutID) -> Bool { if case .embed = kind(id) { return true }; return false }
    func isDocument(_ id: LayoutID) -> Bool { if case .document = kind(id) { return true }; return false }
    func isIframe(_ id: LayoutID) -> Bool { if case .embed(.iframe) = kind(id) { return true }; return false }

    // MARK: Geometry and passes

    func selfRect(_ id: LayoutID) -> Rect {
        switch kind(id) {
        case .block:
            return blockSelfRect(id)
        case .text:
            return textSelfRect(id)
        default:
            let x: CGFloat = x(id)
            let y: CGFloat = y(id)
            return Rect(left: x, top: y, right: x + width(id), bottom: y + height(id))
        }
    }

    /// Transitional dispatch: block and embed passes still take a ref.
    mutating func layout(_ id: LayoutID) {
        switch kind(id) {
        case .document:
            break
        case .block:
            layoutBlock(id)
        case .line:
            layoutLine(id)
        case .text:
            layoutText(id)
        case .embed:
            layoutEmbed(id)
        }
    }

    func layoutNeeded(_ id: LayoutID) -> Bool {
        switch kind(id) {
        case .document:
            return documentLayoutNeeded(id)
        case .block:
            return blockLayoutNeeded(id)
        case .line:
            return lineLayoutNeeded(id)
        case .text:
            return textLayoutNeeded(id)
        case .embed:
            return embedLayoutNeeded(id)
        }
    }
}

// MARK: - Storage

struct LayoutTreeSource {
    var inputs: LayoutInputs
    let dom: DOMTree
    var effects: [LayoutEffect] = []
}
