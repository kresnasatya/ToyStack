import CoreGraphics

// MARK: - FloatLayoutPass

extension LayoutTree {
    /// An anonymous block borrows the style of its first inline node, which
    /// may itself say `float`; only element blocks float or clear.
    func blockFloating(_ id: LayoutID) -> LayoutStyle.Floating {
        guard !hasExtraNodes(id) else { return .none }
        return domView(id).style.computed.layout.position.floating
    }

    /// Floats and absolutely positioned boxes take no space in the flow, so the
    /// next sibling is placed after whatever came before them.
    func isOutOfFlow(_ node: LayoutDOMView) -> Bool {
        let position: LayoutStyle.Positioning = node.style.computed.layout.position
        return position.kind == .absolute || position.floating.side != .none
    }

    /// CSS 2.1 §9.5.2: `clear` looks at every earlier float in the same block
    /// formatting context, including floats under other parents.
    func floatBottom(before id: LayoutID, clearing clear: LayoutStyle.ClearSide) -> CGFloat? {
        return earlierFloats(before: id, where: { clear.clears($0.side) }).map({ $0.rect.bottom }).max()
    }

    /// Where a float's margin box goes. Earlier floats that end above `top`
    /// cannot be beside it, cannot hold it down, and cannot be cleared.
    func floatPlacer(for id: LayoutID, top: CGFloat) -> FloatPlacer {
        guard let parent: LayoutID = parentID(of: id) else {
            return FloatPlacer(earlier: [], left: 0, right: 0)
        }
        let left: CGFloat = x(parent)
        return FloatPlacer(
            earlier: earlierFloats(before: id, where: { $0.rect.bottom > top }),
            left: left,
            right: left + width(parent)
        )
    }

    /// The floats an inline block's lines must avoid: earlier floats in the
    /// same block formatting context that reach below the block's top and
    /// into its content box. A block that starts its own formatting context
    /// keeps outside floats away from its lines.
    func floatExclusions(for id: LayoutID) -> FloatExclusions {
        if !hasExtraNodes(id), establishesFormattingContext(id) { return .none }
        let left: CGFloat = x(id)
        let right: CGFloat = left + width(id)
        let top: CGFloat = y(id)
        var boxes: [FloatBox] = earlierFloats(before: id, where: { box in
            box.rect.bottom > top && intrudes(box, left: left, right: right)
        })
        guard !boxes.isEmpty else { return .none }
        boxes.sort(by: { a, b in
            if a.rect.top != b.rect.top { return a.rect.top < b.rect.top }
            return a.rect.left < b.rect.left
        })
        // CSS 2.1 §10.8.1: every line is at least as tall as the block's strut,
        // so no band a line is checked against is shorter than that.
        let strut: CGFloat = fontFor(id, zoom: zoom(id)).linespace
        return FloatExclusions(boxes: boxes, left: left, right: right, strut: strut)
    }

    /// Registered floats placed before `id` in the same block formatting
    /// context. `include` runs first: it is cheap, the tree-order check is not.
    private func earlierFloats(before id: LayoutID, where include: (FloatBox) -> Bool) -> [FloatBox] {
        let registered: [LayoutID: FloatBox] = self[document: rootID].floats.boxes
        guard !registered.isEmpty else { return [] }
        var root: LayoutID? = nil
        var boxes: [FloatBox] = []
        for (float, box) in registered where float != id && include(box) {
            guard contains(float), precedes(float, id) else { continue }
            if root == nil { root = formattingRoot(of: id) }
            guard formattingRoot(of: float) == root else { continue }
            boxes.append(box)
        }
        return boxes
    }

    /// Returns whether the floats differ from the ones the block's lines were
    /// last broken against.
    mutating func noteWrapped(_ id: LayoutID, _ exclusions: FloatExclusions) -> Bool {
        let old: [FloatBox] = self[document: rootID].floats.wrapped[id] ?? []
        guard old != exclusions.boxes else { return false }
        self[document: rootID].floats.wrapped[id] = exclusions.isEmpty ? nil : exclusions.boxes
        return true
    }

    mutating func notePositioned(_ id: LayoutID, _ readsFloats: Bool) {
        if readsFloats {
            self[document: rootID].floats.positioned.insert(id)
        } else if !self[document: rootID].floats.positioned.isEmpty {
            self[document: rootID].floats.positioned.remove(id)
        }
    }

    /// Called once a block's height is final. A float whose margin box moved
    /// or grew marks the blocks beside its new box; blocks beside its old box
    /// are already in `wrapped` and re-check themselves.
    mutating func recordFloatBox(_ id: LayoutID) {
        let side: LayoutStyle.FloatSide = blockFloating(id).side
        guard side != .none else {
            if self[document: rootID].floats.boxes[id] != nil {
                self[document: rootID].floats.boxes[id] = nil
            }
            return
        }
        let box: FloatBox = FloatBox(side: side, rect: marginBox(id))
        guard self[document: rootID].floats.boxes[id] != box else { return }
        self[document: rootID].floats.boxes[id] = box
        markBlocksBeside(box, after: id)
    }

    /// Floats, clearance, and shortened lines read floats that are not among a
    /// block's layout inputs. Blocks that read them are few, so they re-place
    /// themselves on every pass that does layout work instead.
    mutating func markFloatDependents() {
        var registry: FloatRegistry = self[document: rootID].floats
        guard !registry.boxes.isEmpty || !registry.positioned.isEmpty || !registry.wrapped.isEmpty else {
            return
        }
        registry.boxes = registry.boxes.filter({ contains($0.key) })
        registry.positioned = registry.positioned.filter({ contains($0) && isBlock($0) })
        registry.wrapped = registry.wrapped.filter({ contains($0.key) && isBlock($0.key) })
        self[document: rootID].floats = registry
        for id in registry.positioned {
            markField(.y, at: id)
        }
        for id in registry.wrapped.keys {
            markField(.y, at: id)
        }
    }

    // MARK: - Helpers

    private mutating func markBlocksBeside(_ box: FloatBox, after float: LayoutID) {
        var current: LayoutID = float
        while let parent: LayoutID = parentID(of: current), isBlock(parent) {
            var isAfter: Bool = false
            for sibling in childrenIDs(of: parent) {
                if sibling == current {
                    isAfter = true
                } else if isAfter, !markBeside(sibling, box) {
                    return
                }
            }
            if establishesFormattingContext(parent) { return }
            current = parent
        }
    }

    /// Returns false once the walk has passed below the float: later blocks
    /// in the flow only sit lower. The walk runs ahead of the pass, so it reads
    /// last pass's geometry; a block that moves is visited anyway, and a block
    /// never laid out builds its lines from scratch.
    private mutating func markBeside(_ id: LayoutID, _ box: FloatBox) -> Bool {
        guard isBlock(id) else { return true }
        if !hasExtraNodes(id), isOutOfFlow(domView(id)) { return true }
        guard isUsed(.y, at: id), isUsed(.height, at: id) else { return true }
        let top: CGFloat = storedCGFloat(.y, at: id)
        if top >= box.rect.bottom { return false }
        if top + storedCGFloat(.height, at: id) < box.rect.top { return true }
        if !hasExtraNodes(id), establishesFormattingContext(id) { return true }
        let children: [LayoutID] = childrenIDs(of: id)
        guard children.contains(where: { isBlock($0) }) else {
            markField(.y, at: id)
            return true
        }
        for child in children where !markBeside(child, box) {
            return false
        }
        return true
    }

    /// CSS 2.1 §9.4.1: floats, absolutely positioned boxes, and blocks whose
    /// overflow is not visible start a new block formatting context, as does
    /// the root element.
    private func establishesFormattingContext(_ id: LayoutID) -> Bool {
        guard let parent: LayoutID = parentID(of: id), isBlock(parent) else { return true }
        guard !hasExtraNodes(id) else { return false }
        let layout: LayoutStyle = domView(id).style.computed.layout
        return layout.position.floating.side != .none
            || layout.position.kind == .absolute
            || layout.position.kind == .fixed
            || layout.overflow != .visible
    }

    private func formattingRoot(of id: LayoutID) -> LayoutID? {
        var current: LayoutID? = parentID(of: id)
        while let node: LayoutID = current, isBlock(node) {
            if establishesFormattingContext(node) { return node }
            current = parentID(of: node)
        }
        return nil
    }

    /// Tree order through the nearest common ancestor. A float whose path down
    /// from that ancestor is broken was taken out of the tree this pass (its
    /// parent rebuilt its children) and precedes nothing.
    private func precedes(_ a: LayoutID, _ b: LayoutID) -> Bool {
        let pathA: [LayoutID] = ancestorPath(a)
        let pathB: [LayoutID] = ancestorPath(b)
        var depth: Int = 0
        while depth < pathA.count, depth < pathB.count, pathA[depth] == pathB[depth] {
            depth += 1
        }
        guard depth > 0, depth < pathA.count, depth < pathB.count else { return false }
        for level in (depth + 1)..<pathA.count where !childrenIDs(of: pathA[level - 1]).contains(pathA[level]) {
            return false
        }
        let siblings: [LayoutID] = childrenIDs(of: pathA[depth - 1])
        guard let indexA: Int = siblings.firstIndex(of: pathA[depth]),
            let indexB: Int = siblings.firstIndex(of: pathB[depth])
        else { return false }
        return indexA < indexB
    }

    private func ancestorPath(_ id: LayoutID) -> [LayoutID] {
        var path: [LayoutID] = [id]
        var current: LayoutID = id
        while let parent: LayoutID = parentID(of: current) {
            path.append(parent)
            current = parent
        }
        path.reverse()
        return path
    }

    private func intrudes(_ box: FloatBox, left: CGFloat, right: CGFloat) -> Bool {
        switch box.side {
        case .left: return box.rect.right > left
        case .right: return box.rect.left < right
        case .none: return false
        }
    }

    private func marginBox(_ id: LayoutID) -> Rect {
        let margin: EdgeInsets = domView(id).style.computed.box.spacing.margin.scaled(by: zoom(id))
        return blockSelfRect(id).outset(by: margin)
    }
}
