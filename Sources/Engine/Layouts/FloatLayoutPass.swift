import CoreGraphics

// MARK: - FloatLayoutPass

extension LayoutTree {
    func blockFloating(_ id: LayoutID) -> LayoutStyle.Floating {
        guard !hasExtraNodes(id) else { return .none }
        return domView(id).style.computed.layout.position.floating
    }

    func isOutOfFlow(_ node: LayoutDOMView) -> Bool {
        let position: LayoutStyle.Positioning = node.style.computed.layout.position
        return position.kind == .absolute || position.floating.side != .none
    }

    /// CSS 2.1 §9.5.2: `clear` looks at every earlier float in the same block
    /// formatting context, including floats under other parents.
    func floatBottom(before id: LayoutID, clearing clear: LayoutStyle.ClearSide) -> CGFloat? {
        return earlierFloats(before: id, where: { clear.clears($0.side) }).map({ $0.rect.bottom }).max()
    }

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

    func floatPlacer(inside block: LayoutID, top: CGFloat, own: [FloatBox]) -> FloatPlacer {
        let left: CGFloat = x(block)
        let outside: [FloatBox] = !hasExtraNodes(block) && establishesFormattingContext(block)
            ? []
            : earlierFloats(before: block, where: { $0.rect.bottom > top })
        return FloatPlacer(earlier: outside + own, left: left, right: left + width(block))
    }

    func floatContext(for id: LayoutID) -> [FloatBox] {
        if !hasExtraNodes(id), establishesFormattingContext(id) { return [] }
        let top: CGFloat = y(id)
        return earlierFloats(before: id, where: { $0.rect.bottom > top }).sorted(by: { a, b in
            if a.rect.top != b.rect.top { return a.rect.top < b.rect.top }
            return a.rect.left < b.rect.left
        })
    }

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

    mutating func noteWrapped(_ id: LayoutID, _ boxes: [FloatBox]) -> Bool {
        let old: [FloatBox] = self[document: rootID].floats.wrapped[id] ?? []
        guard old != boxes else { return false }
        self[document: rootID].floats.wrapped[id] = boxes.isEmpty ? nil : boxes
        return true
    }

    mutating func notePositioned(_ id: LayoutID, _ readsFloats: Bool) {
        if readsFloats {
            self[document: rootID].floats.positioned.insert(id)
        } else if !self[document: rootID].floats.positioned.isEmpty {
            self[document: rootID].floats.positioned.remove(id)
        }
    }

    mutating func recordFloatBox(_ id: LayoutID) {
        let side: LayoutStyle.FloatSide = blockFloating(id).side
        let old: FloatBox? = self[document: rootID].floats.boxes[id]
        let box: FloatBox? = side == .none ? nil : FloatBox(side: side, rect: marginBox(id))
        guard old != box else { return }
        self[document: rootID].floats.boxes[id] = box
        markMoved(floatReaders(where: { reader in precedes(id, reader) }))
        if let box {
            markBlocksBeside(box, after: id)
        }
    }

    mutating func markReadersOfDroppedFloats(_ dropped: [LayoutID], parent: LayoutID) {
        let floats: Dictionary<LayoutID, FloatBox>.Keys = self[document: rootID].floats.boxes.keys
        guard !floats.isEmpty else { return }
        let droppedSet: Set<LayoutID> = Set(dropped)
        guard floats.contains(where: { isInside($0, droppedSet) }) else { return }
        markMoved(floatReaders(where: { reader in
            reader != parent && (precedes(parent, reader) || isInside(reader, [parent]))
        }))
    }

    mutating func pruneFloatRegistry() {
        var registry: FloatRegistry = self[document: rootID].floats
        guard !registry.boxes.isEmpty || !registry.positioned.isEmpty || !registry.wrapped.isEmpty else {
            return
        }
        let floatCount: Int = registry.boxes.count
        registry.boxes = registry.boxes.filter({ contains($0.key) })
        registry.positioned = registry.positioned.filter({ contains($0) && isBlock($0) })
        registry.wrapped = registry.wrapped.filter({ contains($0.key) && isBlock($0.key) })
        registry.anchors = registry.anchors.filter({ contains($0.key) })
        self[document: rootID].floats = registry
        guard registry.boxes.count < floatCount else { return }
        markMoved(floatReaders(where: { _ in true }))
    }

    func isPositionedByFloats(_ id: LayoutID) -> Bool {
        return self[document: rootID].floats.positioned.contains(id)
    }

    /// CSS 2.1 §9.4.1: floats, absolutely positioned boxes, and blocks whose
    /// overflow is not visible start a new block formatting context. ToyStack
    /// also starts one at the root element.
    func establishesFormattingContext(_ id: LayoutID) -> Bool {
        guard let parent: LayoutID = parentID(of: id), isBlock(parent) else { return true }
        guard !hasExtraNodes(id) else { return false }
        let layout: LayoutStyle = domView(id).style.computed.layout
        return layout.position.floating.side != .none
            || layout.position.kind == .absolute
            || layout.position.kind == .fixed
            || layout.overflow != .visible
    }

    // MARK: - Helpers

    private func floatReaders(where include: (LayoutID) -> Bool) -> [LayoutID] {
        let registry: FloatRegistry = self[document: rootID].floats
        var readers: [LayoutID] = registry.positioned.filter({ contains($0) && include($0) })
        for reader in registry.wrapped.keys where contains(reader) && include(reader) {
            readers.append(reader)
        }
        return readers
    }

    private mutating func markMoved(_ readers: [LayoutID]) {
        for reader in readers {
            markField(.y, at: reader)
        }
    }

    private func isInside(_ id: LayoutID, _ nodes: Set<LayoutID>) -> Bool {
        var current: LayoutID? = id
        while let node: LayoutID = current {
            if nodes.contains(node) { return true }
            current = parentID(of: node)
        }
        return false
    }

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

    private mutating func markBeside(_ id: LayoutID, _ box: FloatBox) -> Bool {
        guard isBlock(id) else { return true }
        if !hasExtraNodes(id), isOutOfFlow(domView(id)) { return true }
        guard isUsed(.y, at: id), isUsed(.height, at: id) else { return true }
        let top: CGFloat = storedCGFloat(.y, at: id)
        if top >= box.rect.bottom { return false }
        if top + storedCGFloat(.height, at: id) < box.rect.top { return true }
        if !hasExtraNodes(id), establishesFormattingContext(id) {
            markField(.y, at: id)
            return true
        }
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

    private func formattingRoot(of id: LayoutID) -> LayoutID? {
        var current: LayoutID? = parentID(of: id)
        while let node: LayoutID = current, isBlock(node) {
            if establishesFormattingContext(node) { return node }
            current = parentID(of: node)
        }
        return nil
    }

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
