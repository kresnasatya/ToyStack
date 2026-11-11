import CoreGraphics
import Foundation

// MARK: - LayoutTree

/// Nodes are append-only: removing a subtree writes `nil` into the hole and
/// never reuses the ID, so a stale `LayoutID` cannot point at another node.
struct LayoutTree: @unchecked Sendable {
    /// Not optional: unwrapping an optional element copies the whole node
    /// (over 400 bytes) on every read. A removed node stays as a placeholder
    /// with `state.isRemoved`; IDs are never reused.
    private(set) var nodes: [LayoutNode]
    private(set) var primaryByNode: [NodeID: LayoutID]
    var dependencies: DependencyIndex
    private var source: LayoutTreeSource
    private var detached: Set<LayoutID> = []
    var needsSweep: Bool { !detached.isEmpty }
    var textRuns: [LayoutID: TextRun] = [:]
    /// Fragment values are collected while paint migrates off text nodes.
    var collectsInlineBoxes: Bool = true

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
        // The root has no parent to attach it; it is never swept.
        detached.remove(document)
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
        let links: LayoutLinks = LayoutLinks(
            parent: parent,
            previous: previous,
            children: [],
            versions: LinkVersions(children: 0, previous: 0)
        )
        let state: LayoutState = LayoutState(
            fields: LayoutFieldStore(),
            hasDirtyDescendants: false,
            isRemoved: false
        )
        return append(
            LayoutNodeSeed(kind: kind, dom: dom, links: links, state: state)
        )
    }

    mutating func append(_ seed: LayoutNodeSeed) -> LayoutID {
        let id: LayoutID = LayoutID(raw: nodes.count)
        nodes.append(
            LayoutNode(
                kind: seed.kind,
                dom: seed.dom,
                links: seed.links,
                state: seed.state
            )
        )
        detached.insert(id)
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

    mutating func markDocumentGeometryDirty() {
        markField(.width, at: rootID)
        markField(.zoom, at: rootID)
    }

    func documentNeedsLayout(counting: Bool = true) -> Bool {
        return documentLayoutNeeded(rootID, counting: counting)
    }

    var liveIDs: [LayoutID] {
        var ids: [LayoutID] = []
        ids.reserveCapacity(nodes.count)
        for index in nodes.indices where !nodes[index].state.isRemoved {
            ids.append(LayoutID(raw: index))
        }
        return ids
    }

    /// Reading one field through it copies only that field, and writing
    /// through it changes the stored node without copying the rest of it
    /// (kind payload, children, font).
    subscript(node id: LayoutID) -> LayoutNode {
        _read {
            guard !nodes[id.raw].state.isRemoved else {
                preconditionFailure("LayoutID points at a removed node")
            }
            yield nodes[id.raw]
        }
        _modify {
            guard !nodes[id.raw].state.isRemoved else {
                preconditionFailure("LayoutID points at a removed node")
            }
            yield &nodes[id.raw]
        }
    }

    func kind(_ id: LayoutID) -> LayoutKind {
        return self[node: id].kind
    }

    func contains(_ id: LayoutID) -> Bool {
        guard id.raw >= 0, id.raw < nodes.count else { return false }
        return !nodes[id.raw].state.isRemoved
    }

    mutating func setKind(_ kind: LayoutKind, at id: LayoutID) {
        self[node: id].kind = kind
    }

    // MARK: - Links

    func children(of id: LayoutID) -> [LayoutID] {
        return self[node: id].links.children
    }

    mutating func setChildren(_ children: [LayoutID], of id: LayoutID) {
        let old: [LayoutID] = self[node: id].links.children
        if old != children {
            let kept: Set<LayoutID> = Set(children)
            // A child that another parent already adopted is still in the tree.
            for child in old where !kept.contains(child)
                && contains(child) && self[node: child].links.parent == id
            {
                detached.insert(child)
            }
            for child in children {
                detached.remove(child)
            }
        }
        self[node: id].links.children = children
        self[node: id].links.versions.children += 1
        for child in children where self[node: child].links.parent != id {
            self[node: child].links.parent = id
        }
    }

    mutating func setPrevious(_ previous: LayoutID?, of id: LayoutID) {
        guard self[node: id].links.previous != previous else { return }
        self[node: id].links.previous = previous
        self[node: id].links.versions.previous += 1
    }

    mutating func removeSubtree(_ id: LayoutID) {
        guard contains(id) else { return }
        let parent: LayoutID? = self[node: id].links.parent
        if let parent {
            self[node: parent].links.children.removeAll(where: { $0 == id })
            self[node: parent].links.versions.children += 1
        }
        var removed: [LayoutID] = []
        collectSubtreeIDs(id, into: &removed)
        removeDependencyEdges(for: Set(removed))
        removeRecursively(id)
        if let parent {
            reindexDependencies(parent)
        }
    }

    private func collectSubtreeIDs(_ id: LayoutID, into ids: inout [LayoutID]) {
        guard contains(id) else { return }
        ids.append(id)
        for child in self[node: id].links.children {
            collectSubtreeIDs(child, into: &ids)
        }
    }

    mutating private func removeRecursively(_ id: LayoutID) {
        guard contains(id) else { return }
        for child in self[node: id].links.children {
            removeRecursively(child)
        }
        let dom: NodeID = self[node: id].dom
        if let primary: LayoutID = primaryByNode[dom], primary == id {
            primaryByNode.removeValue(forKey: dom)
        }
        nodes[id.raw] = .removed(dom: dom)
    }

    /// Must run before the nodes are cleared, because the used-field mask is
    /// read from each node.
    mutating func removeDependencyEdges(for ids: Set<LayoutID>) {
        guard !ids.isEmpty else { return }
        profiler.measure("layout.sweep.edges.dependents", {
            for id in ids {
                guard contains(id) else { continue }
                let mask: UInt16 = self[node: id].state.fields.state.usedBits
                for field in LayoutField.allCases where mask & field.mask != 0 {
                    dependencies.removeDependent(
                        .layout(id, field),
                        skippingRemoved: ids
                    )
                }
            }
        })
        profiler.measure("layout.sweep.edges.keys", {
            for id in ids {
                guard contains(id) else { continue }
                let mask: UInt16 = self[node: id].state.fields.state.usedBits
                for field in LayoutField.allCases where mask & field.mask != 0 {
                    dependencies.removeInputKey(.layout(id, field))
                }
            }
        })
    }

    @discardableResult
    mutating func sweepUnreachable() -> Set<LayoutID> {
        var removed: Set<LayoutID> = []
        var examined: Int = 0
        profiler.measure("layout.sweep.identify", {
            for candidate in detached where contains(candidate) {
                collectDetachedSubtree(candidate, into: &removed, examined: &examined)
            }
        })
        profiler.count("layout.sweep.examined", by: examined)
        #if DEBUG
        assertSweepMatchesReachability(removed)
        #endif
        for id in removed {
            let dom: NodeID = self[node: id].dom
            if let primary: LayoutID = primaryByNode[dom], primary == id {
                primaryByNode.removeValue(forKey: dom)
            }
        }
        removeDependencyEdges(for: removed)
        profiler.measure("layout.sweep.nodes", {
            for id in removed {
                nodes[id.raw] = .removed(dom: nodes[id.raw].dom)
            }
        })
        detached.removeAll(keepingCapacity: true)
        return removed
    }

    /// A child another parent adopted is skipped: its parent link points
    /// elsewhere.
    private func collectDetachedSubtree(
        _ id: LayoutID,
        into removed: inout Set<LayoutID>,
        examined: inout Int
    ) {
        examined += 1
        guard removed.insert(id).inserted else { return }
        for child in self[node: id].links.children
            where contains(child) && self[node: child].links.parent == id
        {
            collectDetachedSubtree(child, into: &removed, examined: &examined)
        }
    }

    #if DEBUG
    private func assertSweepMatchesReachability(_ removed: Set<LayoutID>) {
        var reachable: Set<LayoutID> = []
        collectReachable(rootID, into: &reachable)
        let unreachable: Set<LayoutID> = Set(liveIDs).subtracting(reachable)
        assert(
            removed == unreachable,
            "Targeted sweep dropped \(removed.count) nodes; \(unreachable.count) are unreachable"
        )
    }

    private func collectReachable(_ id: LayoutID, into reachable: inout Set<LayoutID>) {
        guard contains(id), !reachable.contains(id) else { return }
        reachable.insert(id)
        for child in self[node: id].links.children {
            collectReachable(child, into: &reachable)
        }
    }
    #endif

    // MARK: - Style changes

    mutating func consumeStyleChanges() {
        var changed: [NodeID] = []
        profiler.measure("layout.styleChanges.scan", {
            changed = Array(inputs.styleChanges.keys)
        })
        profiler.count("layout.styleChanges.node.count", by: changed.count)

        var affected: Set<LayoutID> = []
        profiler.measure("layout.styleChanges.affected", {
            for node in changed {
                for property in inputs.styleChanges(node)
                where LayoutInputTable.structuralStyleProperties.contains(property) {
                    for dependent in dependencies.fields(for: .style(node, property)) {
                        guard case .layout(let id, _) = dependent else { continue }
                        affected.insert(id)
                    }
                }
            }
        })
        profiler.count("layout.styleChanges.affected.count", by: affected.count)

        profiler.measure("layout.styleChanges.reindex", {
            for id in affected {
                reindexDependencies(id)
            }
        })

        profiler.measure("layout.styleChanges.mark", {
            for node in changed {
                for property in inputs.styleChanges(node) {
                    markDependents(of: .style(node, property))
                }
            }
        })
    }

    mutating func consumeStyleChanges(for node: NodeID) {
        for property in inputs.styleChanges(node) {
            markDependents(of: .style(node, property))
        }
    }

    mutating func clearStyleChanges() {
        source.inputs.styleChanges.removeAll(keepingCapacity: true)
    }

    // MARK: - Fields
    func isDirty(_ field: LayoutField, at id: LayoutID) -> Bool {
        return self[node: id].state.fields.isDirty(field)
    }

    func isUsed(_ field: LayoutField, at id: LayoutID) -> Bool {
        return self[node: id].state.fields.isUsed(field)
    }

    mutating func markUsed(_ field: LayoutField, at id: LayoutID) {
        let wasUsed: Bool = self[node: id].state.fields.isUsed(field)
        self[node: id].state.fields.markUsed(field)
        guard !wasUsed else { return }
        let dependent: FieldKey = .layout(id, field)
        for input in LayoutInputTable.inputs(for: id, field: field, in: self) {
            dependencies.add(dependent, for: input)
        }
    }

    mutating func reindexDependencies(
        _ id: LayoutID,
        fields: [LayoutField] = LayoutField.allCases
    ) {
        var inputs: [LayoutField: [FieldKey]] = [:]
        for field in fields where isUsed(field, at: id) {
            inputs[field] = LayoutInputTable.inputs(for: id, field: field, in: self)
        }
        dependencies.reindex(id, fields: fields, inputs: inputs)
    }

    mutating func markClean(_ field: LayoutField, at id: LayoutID) {
        self[node: id].state.fields.markClean(field)
    }

    mutating func markField(_ field: LayoutField, at id: LayoutID) {
        guard !isDirty(field, at: id) else { return }
        profiler.count("layout.field.mark")
        self[node: id].state.fields.markDirty(field)
        markAncestorsDirty(from: id)
    }

    mutating func markAncestorsDirty(from id: LayoutID) {
        var current: LayoutID? = self[node: id].links.parent
        while let ancestor = current, !self[node: ancestor].state.hasDirtyDescendants {
            self[node: ancestor].state.hasDirtyDescendants = true
            current = self[node: ancestor].links.parent
        }
    }

    mutating func setDirtyDescendants(_ value: Bool, at id: LayoutID) {
        self[node: id].state.hasDirtyDescendants = value
    }

    // MARK: - Values

    func storedCGFloat(_ field: LayoutField, at id: LayoutID) -> CGFloat {
        switch field {
        case .x:
            return self[node: id].state.fields.geometry.origin.x
        case .y:
            return self[node: id].state.fields.geometry.origin.y
        case .width:
            return self[node: id].state.fields.geometry.size.width
        case .height:
            return self[node: id].state.fields.geometry.size.height
        case .zoom:
            return self[node: id].state.fields.geometry.zoom
        case .ascent:
            return self[node: id].state.fields.inlineText.ascent
        case .descent:
            return self[node: id].state.fields.inlineText.descent
        default:
            preconditionFailure("Field \(field.rawValue) is not a CGFloat value")
        }
    }

    func storedFont(_ id: LayoutID) -> BrowserFont {
        return self[node: id].state.fields.inlineText.font
    }

    func storedInlineContent(_ id: LayoutID) -> UInt64 {
        return self[node: id].state.fields.inlineText.inlineContent
    }

    mutating private func writeCGFloat(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        switch field {
        case .x:
            self[node: id].state.fields.geometry.origin.x = value
        case .y:
            self[node: id].state.fields.geometry.origin.y = value
        case .width:
            self[node: id].state.fields.geometry.size.width = value
        case .height:
            self[node: id].state.fields.geometry.size.height = value
        case .zoom:
            self[node: id].state.fields.geometry.zoom = value
        case .ascent:
            self[node: id].state.fields.inlineText.ascent = value
        case .descent:
            self[node: id].state.fields.inlineText.descent = value
        default:
            preconditionFailure("Field \(field.rawValue) is not a CGFloat value")
        }
    }

    mutating private func writeFont(_ font: BrowserFont, for id: LayoutID) {
        self[node: id].state.fields.inlineText.font = font
    }

    mutating private func writeInlineContent(_ value: UInt64, for id: LayoutID) {
        self[node: id].state.fields.inlineText.inlineContent = value
    }

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

    /// Static, so a call does not allocate an array.
    private static let frameFields: [LayoutField] = [.zoom, .x, .y, .width]
    private static let positionFields: [LayoutField] = [.x, .y]
    private static let textMetricFields: [LayoutField] = [.width, .height, .ascent, .descent]

    mutating func setFrame(
        _ frame: (zoom: CGFloat, x: CGFloat, y: CGFloat, width: CGFloat),
        for id: LayoutID
    ) {
        let old: GeometryFields = self[node: id].state.fields.geometry
        let used: UInt16 = self[node: id].state.fields.state.usedBits
        self[node: id].state.fields.geometry.zoom = frame.zoom
        self[node: id].state.fields.geometry.origin.x = frame.x
        self[node: id].state.fields.geometry.origin.y = frame.y
        self[node: id].state.fields.geometry.size.width = frame.width
        markUsedClean(Self.frameFields, at: id)
        registerInputs(of: Self.frameFields, notIn: used, for: id)

        if used & LayoutField.zoom.mask == 0 || old.zoom != frame.zoom {
            noteFieldSet(.zoom, at: id)
        }
        if used & LayoutField.x.mask == 0 || old.origin.x != frame.x {
            noteFieldSet(.x, at: id)
        }
        if used & LayoutField.y.mask == 0 || old.origin.y != frame.y {
            noteFieldSet(.y, at: id)
        }
        if used & LayoutField.width.mask == 0 || old.size.width != frame.width {
            noteFieldSet(.width, at: id)
        }
    }

    mutating func setPosition(x: CGFloat, y: CGFloat, for id: LayoutID) {
        let old: Point = self[node: id].state.fields.geometry.origin
        let used: UInt16 = self[node: id].state.fields.state.usedBits
        self[node: id].state.fields.geometry.origin.x = x
        self[node: id].state.fields.geometry.origin.y = y
        markUsedClean(Self.positionFields, at: id)

        if used & LayoutField.x.mask == 0 || old.x != x {
            noteFieldSet(.x, at: id)
        }
        if used & LayoutField.y.mask == 0 || old.y != y {
            noteFieldSet(.y, at: id)
        }
    }

    mutating func setFieldClean(_ field: LayoutField, _ value: CGFloat, for id: LayoutID) {
        writeCGFloat(field, value, for: id)
        markUsed(field, at: id)
        markClean(field, at: id)
    }

    mutating func setFont(_ font: BrowserFont, for id: LayoutID) {
        let fields: FieldState = self[node: id].state.fields.state
        let wasUsed: Bool = fields.isUsed(.font)
        let changed: Bool = !wasUsed
            || !CFEqual(self[node: id].state.fields.inlineText.font.ctFont, font.ctFont)
        if wasUsed, !fields.isDirty(.font), !changed { return }
        self[node: id].state.fields.inlineText.font = font
        self[node: id].state.fields.markUsed(.font)
        self[node: id].state.fields.markClean(.font)
        if !wasUsed {
            let dependent: FieldKey = .layout(id, .font)
            for input in LayoutInputTable.inputs(for: id, field: .font, in: self) {
                dependencies.add(dependent, for: input)
            }
        }
        guard changed else { return }
        profiler.count("layout.field.set")
        markDependents(of: .layout(id, .font))
    }

    mutating func setFontAndPrevious(
        _ font: BrowserFont,
        previous: LayoutID?,
        measuredWidth: CGFloat?,
        for id: LayoutID
    ) {
        let fields: FieldState = self[node: id].state.fields.state
        let wasUsed: Bool = fields.isUsed(.font)
        let fontDirty: Bool = fields.isDirty(.font)
        let changed: Bool = !wasUsed
            || !CFEqual(self[node: id].state.fields.inlineText.font.ctFont, font.ctFont)
        let previousChanged: Bool = self[node: id].links.previous != previous
        var metricsChanged: Bool = false
        if let measuredWidth: CGFloat {
            if case .text(var data) = self[node: id].kind,
                data.metrics.width != measuredWidth || !data.metrics.measured
            {
                data.metrics.width = measuredWidth
                data.metrics.measured = true
                self[node: id].kind = .text(data)
                metricsChanged = true
            }
        }
        let needsWrite: Bool = !wasUsed || changed || fontDirty || previousChanged || metricsChanged
        guard needsWrite else { return }
        if !wasUsed || changed || fontDirty {
            self[node: id].state.fields.inlineText.font = font
            self[node: id].state.fields.markUsed(.font)
            self[node: id].state.fields.markClean(.font)
        }
        if previousChanged {
            self[node: id].links.previous = previous
            self[node: id].links.versions.previous += 1
        }
        if !wasUsed {
            let dependent: FieldKey = .layout(id, .font)
            for input in LayoutInputTable.inputs(for: id, field: .font, in: self) {
                dependencies.add(dependent, for: input)
            }
        }
        guard changed else { return }
        profiler.count("layout.field.set")
        markDependents(of: .layout(id, .font))
    }

    mutating func setFontClean(_ font: BrowserFont, for id: LayoutID) {
        writeFont(font, for: id)
        markUsed(.font, at: id)
        markClean(.font, at: id)
    }

    mutating func setTextMetrics(
        _ id: LayoutID,
        width: CGFloat,
        vertical: (height: CGFloat, ascent: CGFloat, descent: CGFloat)
    ) {
        let used: UInt16 = self[node: id].state.fields.state.usedBits
        for field in Self.textMetricFields where used & field.mask == 0 {
            markUsed(field, at: id)
        }
        let oldSize: CGSize = self[node: id].state.fields.geometry.size
        let oldAscent: CGFloat = self[node: id].state.fields.inlineText.ascent
        let oldDescent: CGFloat = self[node: id].state.fields.inlineText.descent

        self[node: id].state.fields.geometry.size.width = width
        self[node: id].state.fields.geometry.size.height = vertical.height
        self[node: id].state.fields.inlineText.ascent = vertical.ascent
        self[node: id].state.fields.inlineText.descent = vertical.descent
        markUsedClean(Self.textMetricFields, at: id)

        if used & LayoutField.width.mask == 0 || oldSize.width != width {
            noteFieldSet(.width, at: id)
        }
        if used & LayoutField.height.mask == 0 || oldSize.height != vertical.height {
            noteFieldSet(.height, at: id)
        }
        if used & LayoutField.ascent.mask == 0 || oldAscent != vertical.ascent {
            noteFieldSet(.ascent, at: id)
        }
        if used & LayoutField.descent.mask == 0 || oldDescent != vertical.descent {
            noteFieldSet(.descent, at: id)
        }
    }

    private mutating func markUsedClean(_ fields: [LayoutField], at id: LayoutID) {
        for field in fields {
            self[node: id].state.fields.markUsed(field)
            self[node: id].state.fields.markClean(field)
        }
    }

    private mutating func registerInputs(of fields: [LayoutField], notIn used: UInt16, for id: LayoutID) {
        for field in fields where used & field.mask == 0 {
            let dependent: FieldKey = .layout(id, field)
            for input in LayoutInputTable.inputs(for: id, field: field, in: self) {
                dependencies.add(dependent, for: input)
            }
        }
    }

    private mutating func noteFieldSet(_ field: LayoutField, at id: LayoutID) {
        profiler.count("layout.field.set")
        markDependents(of: .layout(id, field))
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

    mutating func setInlineChildrenField(_ children: [LayoutID], of id: LayoutID) {
        let wasUsed: Bool = isUsed(.children, at: id)
        let changed: Bool = profiler.measure("layout.inline.children.compare", {
            !wasUsed || self.children(of: id) != children
        })
        let reparented: [LayoutID] = profiler.measure("layout.inline.children.reparent", {
            children.filter({ self[node: $0].links.parent != id })
        })
        profiler.measure("layout.inline.children.write", {
            markUsed(.children, at: id)
            setChildren(children, of: id)
            markClean(.children, at: id)
        })
        if changed || !reparented.isEmpty {
            profiler.measure("layout.inline.children.deps", {
                if isUsed(.height, at: id) {
                    dependencies.replaceDependent(
                        .layout(id, .height),
                        with: blockHeightInputs(id)
                    )
                }
            })
            if !reparented.isEmpty {
                profiler.measure("layout.inline.children.reindex", {
                    for child in reparented {
                        reindexDependencies(child)
                    }
                })
            }
        }
        if changed {
            profiler.count("layout.field.set")
            markDependents(of: .layout(id, .children))
        }
    }

    mutating func setLineChildrenField(
        _ children: [LayoutID],
        of id: LayoutID,
        previousChanged: Bool
    ) {
        let wasUsed: Bool = isUsed(.children, at: id)
        let oldChildren: [LayoutID] = self.children(of: id)
        let changed: Bool = profiler.measure("layout.line.children.compare", {
            !wasUsed || oldChildren != children
        })
        let reparented: [LayoutID] = profiler.measure("layout.line.children.reparent", {
            children.filter({ self[node: $0].links.parent != id })
        })
        var oldParents: [LayoutID: LayoutID] = [:]
        if !reparented.isEmpty {
            for child in reparented {
                if let parent: LayoutID = parentID(of: child) {
                    oldParents[child] = parent
                }
            }
        }
        if changed || !reparented.isEmpty {
            profiler.measure("layout.line.children.write", {
                markUsed(.children, at: id)
                setChildren(children, of: id)
                markClean(.children, at: id)
            })
        }

        if changed {
            profiler.measure("layout.line.children.deps", {
                for field in [LayoutField.ascent, .descent] where isUsed(field, at: id) {
                    dependencies.replaceDependent(
                        .layout(id, field),
                        with: children.map({ .layout($0, field) })
                    )
                }
                dependencies.removeDependent(.layout(id, .children))
            })
        }

        if previousChanged {
            profiler.measure("layout.line.children.previous", {
                let parent: LayoutID? = parentID(of: id)
                let previous: LayoutID? = previousID(of: id)
                var yInputs: [FieldKey] = parent.map({ [.layout($0, .y)] }) ?? []
                if let previous {
                    yInputs += [.layout(previous, .y), .layout(previous, .height)]
                }
                dependencies.replaceDependent(.layout(id, .y), with: yInputs)
            })
        }

        if !reparented.isEmpty {
            profiler.measure("layout.line.children.reindex", {
                for child in reparented {
                    if isText(child), let oldParent: LayoutID = oldParents[child] {
                        dependencies.replaceInput(
                            .layout(child, .zoom),
                            old: .layout(oldParent, .zoom),
                            new: .layout(id, .zoom)
                        )
                    } else {
                        let fields: [LayoutField] = isText(child) ? [.zoom] : LayoutField.allCases
                        reindexDependencies(child, fields: fields)
                    }
                }
            })
        }
        if changed {
            profiler.count("layout.field.set")
            markDependents(of: .layout(id, .children))
        }
    }

    mutating func setChildrenField(_ children: [LayoutID], of id: LayoutID) {
        let wasUsed: Bool = isUsed(.children, at: id)
        let changed: Bool = !wasUsed || self.children(of: id) != children
        let reparented: [LayoutID] = children.filter({ self[node: $0].links.parent != id })
        markUsed(.children, at: id)
        setChildren(children, of: id)
        markClean(.children, at: id)
        if changed || !reparented.isEmpty {
            let fields: [LayoutField] = isLine(id)
                ? [.y, .ascent, .descent, .height]
                : LayoutField.allCases
            reindexDependencies(id, fields: fields)
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
        let changed: Bool = !wasUsed || self[node: id].links.previous != previous
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
    // Reading copies only what the caller reads. Writing moves the payload out
    // of the node for the duration, so the arrays inside are changed without
    // being copied; the node holds `vacatedKind` meanwhile, and exclusive
    // access to the tree means nothing can read it in between.

    subscript(document id: LayoutID) -> DocumentData {
        _read {
            switch self[node: id].kind {
            case .document(let data):
                yield data
            default:
                preconditionFailure("Not a document node")
            }
        }
        _modify {
            guard case .document(var data) = self[node: id].kind else {
                preconditionFailure("Not a document node")
            }
            defer { self[node: id].kind = .document(data) }
            yield &data
        }
    }

    subscript(block id: LayoutID) -> BlockData {
        _read {
            switch self[node: id].kind {
            case .block(let data):
                yield data
            default:
                preconditionFailure("Not a block node")
            }
        }
        _modify {
            guard case .block(var data) = self[node: id].kind else {
                preconditionFailure("Not a block node")
            }
            self[node: id].kind = Self.vacatedKind
            defer { self[node: id].kind = .block(data) }
            yield &data
        }
    }

    private static let vacatedKind: LayoutKind = .document(DocumentData(pageZoom: 1))

    subscript(line id: LayoutID) -> LineData {
        _read {
            switch self[node: id].kind {
            case .line(let data):
                yield data
            default:
                preconditionFailure("Not a line node")
            }
        }
        _modify {
            guard case .line(var data) = self[node: id].kind else {
                preconditionFailure("Not a line node")
            }
            self[node: id].kind = Self.vacatedKind
            defer { self[node: id].kind = .line(data) }
            yield &data
        }
    }

    subscript(text id: LayoutID) -> TextData {
        _read {
            switch self[node: id].kind {
            case .text(let data):
                yield data
            default:
                preconditionFailure("Not a text node")
            }
        }
        _modify {
            guard case .text(var data) = self[node: id].kind else {
                preconditionFailure("Not a text node")
            }
            self[node: id].kind = Self.vacatedKind
            defer { self[node: id].kind = .text(data) }
            yield &data
        }
    }

    func textString(_ id: LayoutID) -> String {
        let data: TextData = self[text: id]
        if let fragment = data.fragment, let run: TextRun = textRuns[fragment.block] {
            return run.string(start: fragment.start, count: fragment.count)
        }
        return data.payload.display ?? data.payload.word
    }

    func inlineBoxes(for dom: NodeID) -> [InlineBox] {
        var result: [InlineBox] = []
        for id in liveIDs where isLine(id) {
            let boxes: [InlineBox] = currentInlineBoxes(id)
                ?? self[line: id].content.boxes
            for box in boxes where box.dom == dom {
                result.append(
                    InlineBox(
                        dom: box.dom,
                        fragment: box.fragment,
                        geometry: InlineBoxGeometry(
                            x: box.geometry.x,
                            y: y(id) + box.geometry.y,
                            width: box.geometry.width
                        ),
                        text: box.text
                    )
                )
            }
        }
        return result
    }

    func inlineText(_ box: InlineBox) -> String {
        if let fragment = box.fragment, let run: TextRun = textRuns[fragment.block] {
            return run.string(start: fragment.start, count: fragment.count)
        }
        return box.text.payload.display ?? box.text.payload.word
    }

    subscript(embed id: LayoutID) -> EmbedData {
        _read {
            switch self[node: id].kind {
            case .embed(let data):
                yield data
            default:
                preconditionFailure("Not an embed node")
            }
        }
        _modify {
            guard case .embed(var data) = self[node: id].kind else {
                preconditionFailure("Not an embed node")
            }
            self[node: id].kind = Self.vacatedKind
            defer { self[node: id].kind = .embed(data) }
            yield &data
        }
    }

    // MARK: Structure

    func domID(of id: LayoutID) -> NodeID { return self[node: id].dom }
    func parentID(of id: LayoutID) -> LayoutID? { return self[node: id].links.parent }
    func previousID(of id: LayoutID) -> LayoutID? { return self[node: id].links.previous }
    func childrenIDs(of id: LayoutID) -> [LayoutID] { return self[node: id].links.children }
    func hasDirtyDescendants(at id: LayoutID) -> Bool { return self[node: id].state.hasDirtyDescendants }

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
