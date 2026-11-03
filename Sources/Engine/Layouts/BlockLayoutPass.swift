import CoreGraphics

// MARK: - BlockLayoutPass

extension LayoutTree {
    static let hiddenElements: Set<String> = ["head", "title", "script", "style"]

    // MARK: - Construction

    mutating func makeBlock(
        dom: NodeID,
        parent: LayoutID,
        previous: LayoutID?
    ) -> LayoutID {
        let id: LayoutID = append(
            kind: .block(BlockData()),
            dom: dom,
            parent: parent,
            previous: previous
        )
        setPrimary(id, for: dom)
        initializeBlock(id, extraNodes: [], previous: previous)
        addDependencyEdges(for: id)
        return id
    }

    mutating func makeAnonymousBlock(
        extraNodes: [NodeID],
        parent: LayoutID,
        previous: LayoutID?
    ) -> LayoutID {
        precondition(!extraNodes.isEmpty)
        let id: LayoutID = append(
            kind: .block(BlockData()),
            dom: extraNodes[0],
            parent: parent,
            previous: previous
        )
        initializeBlock(id, extraNodes: extraNodes, previous: previous)
        addDependencyEdges(for: id)
        return id
    }

    mutating private func initializeBlock(
        _ id: LayoutID,
        extraNodes: [NodeID],
        previous: LayoutID?
    ) {
        var data: BlockData = blockData(id)
        data.content.extraNodes = extraNodes
        setKind(.block(data), at: id)
        setPreviousClean(previous, of: id)
        for field in [
            LayoutField.zoom, .x, .y, .width, .inlineContent, .children,
        ] {
            markUsed(field, at: id)
        }
        markAncestorsDirty(from: id)
    }

    func blockExtraNodes(_ id: LayoutID) -> [LayoutDOMView] {
        return blockData(id).content.extraNodes.map({ domView($0) })
    }

    func inlineContentInputs(_ id: LayoutID) -> [FieldKey] {
        let extraNodes: [LayoutDOMView] = blockExtraNodes(id)
        var inputs: [FieldKey] = [
            .layout(id, .zoom),
            .style(domID(of: id), .display),
            .style(domID(of: id), .position),
            .style(domID(of: id), .direction),
        ]
        if extraNodes.isEmpty {
            for child in domView(id).children {
                inputs.append(.style(child.id, .display))
                inputs.append(.style(child.id, .position))
            }
        }
        for leaf in inlineLeaves(id) {
            let owner: LayoutDOMView = leaf.inheritedStyleOwner
            inputs.append(.style(owner.id, .whiteSpace))
            inputs.append(contentsOf: fontInputs(for: leaf.id, in: self.inputs))
            if let el = leaf.element {
                inputs.append(.style(el.ref.id, .aspectRatio))
                inputs.append(.style(el.ref.id, .maxWidth))
            }
        }
        return inputs
    }

    // Only leaves this block lays out inline. Nested blocks own their own inputs.
    private func inlineLeaves(_ id: LayoutID) -> [LayoutDOMView] {
        var leaves: [LayoutDOMView] = []
        let extraNodes: [LayoutDOMView] = blockExtraNodes(id)
        if !extraNodes.isEmpty {
            for node in extraNodes { collectLeaves(node, into: &leaves) }
            return leaves
        }
        let hasBlockChild: Bool = domView(id).children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if !hasBlockChild {
            collectLeaves(domView(id), into: &leaves)
            return leaves
        }
        for child in domView(id).children where child.style.computed.layout.display != .block {
            collectLeaves(child, into: &leaves)
        }
        return leaves
    }

    // MARK: - Line plan

    mutating private func inlineTextLinePlan(_ id: LayoutID) -> [[Int]]? {
        let items: [InlineItem] = blockData(id).content.inlineItems
        var plan: [[Int]] = []
        var current: [Int] = []
        var cursorX: CGFloat = 0
        let availableWidth: CGFloat = width(id)
        var updated: [InlineItem] = items

        for index in updated.indices {
            switch updated[index] {
            case .lineBreak:
                plan.append(current)
                current = []
                cursorX = 0
            case .embed:
                return nil
            case .text(var text):
                if text.hasSoftHypen { return nil }
                let font: BrowserFont = text.fontOverride ?? text.run.font
                let wordWidth: CGFloat
                if let cached: CGFloat = text.measuredWidth {
                    wordWidth = cached
                } else {
                    wordWidth = font.measure(text.display ?? text.word)
                    text.measuredWidth = wordWidth
                    updated[index] = .text(text)
                }
                let width: CGFloat = wordWidth + font.spaceWidth
                if cursorX + width > availableWidth && text.run.whiteSpace.wraps {
                    plan.append(current)
                    current = []
                    cursorX = 0
                }
                current.append(index)
                cursorX += width
            }
        }

        var data: BlockData = blockData(id)
        data.content.inlineItems = updated
        setKind(.block(data), at: id)
        plan.append(current)
        return plan
    }

    mutating private func setHeightInputs(_ id: LayoutID) {
        let children: [LayoutID] = childrenIDs(of: id)
        let declared: [LayoutID] = blockData(id).changes.declaredHeightChildren
        let unchanged: Bool = children == declared
        if unchanged { return }
        var data: BlockData = blockData(id)
        data.changes.declaredHeightChildren = children
        setKind(.block(data), at: id)
        markUsed(.height, at: id)
        addDependencyEdges(for: id)
    }

    func blockHeightInputs(_ id: LayoutID) -> [FieldKey] {
        var inputs: [FieldKey] = [
            .layout(id, .children),
            .layout(id, .zoom),
            .style(domID(of: id), .height),
            .style(domID(of: id), .overflow),
        ]
        for child in childrenIDs(of: id) {
            inputs.append(.layout(child, .height))
            inputs.append(.style(domID(of: child), .position))
            inputs.append(.style(domID(of: child), .marginTop))
            inputs.append(.style(domID(of: child), .marginBottom))
            if isBlock(child) {
                inputs.append(.layout(child, .zoom))
                inputs.append(.style(domID(of: child), .paddingTop))
                inputs.append(.style(domID(of: child), .paddingBottom))
            }
        }
        return inputs
    }

    mutating func blockMarkChildrenDirty(_ id: LayoutID) {
        var data: BlockData = blockData(id)
        data.changes.childChanges.removeAll()
        setKind(.block(data), at: id)
        markField(.inlineContent, at: id)
        markField(.children, at: id)
    }

    mutating func blockNoteAppendedChildren(_ id: LayoutID, _ nodes: [NodeID]) {
        var data: BlockData = blockData(id)
        data.changes.childChanges.append(.append(nodes))
        setKind(.block(data), at: id)
        markAncestorsDirty(from: id)
    }

    mutating func blockNoteInsertedChildren(_ id: LayoutID, _ nodes: [NodeID], before reference: NodeID) {
        var data: BlockData = blockData(id)
        data.changes.childChanges.append(.insert(nodes, before: reference))
        setKind(.block(data), at: id)
        markAncestorsDirty(from: id)
    }

    mutating func setBlockPrevious(_ id: LayoutID, _ newValue: LayoutID?) {
        setPreviousField(newValue, of: id)
    }

    func blockPrevious(_ id: LayoutID) -> LayoutID? {
        return previousID(of: id)
    }

    func blockLayoutNeeded(_ id: LayoutID) -> Bool {
        if hasDirtyDescendants(at: id) {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: LayoutFieldStore = node(id).state.fields
        if state.isDirty(.zoom) || state.isDirty(.x) || state.isDirty(.y)
            || state.isDirty(.width) || state.isDirty(.height)
        {
            return true
        }
        return state.isDirty(.inlineContent)
            || state.isDirty(.children)
            || !blockData(id).changes.childChanges.isEmpty
    }

    mutating func layoutBlock(_ id: LayoutID) {
        guard blockLayoutNeeded(id) else {
            profiler.count("layout.skipped")
            return
        }
        defer { setDirtyDescendants(false, at: id) }
        profiler.count("layout.visited")
        let style: BlockStyle = blockStyle(id)
        profiler.measure("layout.visit") {
            profiler.count("layout.rebuilt")
            setField(.zoom, resolvedZoom(id), for: id)
            let isAbsolute: Bool = style.position == .absolute

            let parentX: CGFloat = x(parentID(of: id)!)
            let padLeft: CGFloat = blockExtraNodes(id).isEmpty ? style.box.padding.left * zoom(id) : 0
            if isAbsolute, let l = style.flags.left {
                let absoluteXZoom: CGFloat = zoom(id)
                setField(.x, l * absoluteXZoom + padLeft, for: id)
            } else {
                setField(.x, parentX + padLeft, for: id)
            }

            let parentWidth: CGFloat = width(parentID(of: id)!)
            let blockZoom: CGFloat = zoom(id)
            let padHorizontal: CGFloat = blockExtraNodes(id).isEmpty
                ? (style.box.padding.left + style.box.padding.right) * blockZoom
                : 0
            if let w = style.box.width {
                setField(.width, w * blockZoom, for: id)
            } else {
                setField(.width, max(0, parentWidth - padHorizontal), for: id)
            }

            if let el = domView(id).element, el.tag == "li" {
                setField(.x, x(id) + liIndent, for: id)
                setField(.width, width(id) - liIndent, for: id)
            }

            if isAbsolute, let t = style.flags.top {
                let absoluteYZoom: CGFloat = zoom(id)
                let padTop: CGFloat = blockExtraNodes(id).isEmpty ? style.box.padding.left * blockZoom : 0
                setField(.y, t * absoluteYZoom + padTop, for: id)
            } else {
                let ownTop: CGFloat = style.box.margin.top * blockZoom
                let padTop: CGFloat = style.box.padding.top * blockZoom
                if let previous: LayoutID = blockPrevious(id) {
                    let prevY: CGFloat = y(previous)
                    let prevHeight: CGFloat = height(previous)
                    let prevPadBottom: CGFloat = isBlock(previous)
                        ? padding(previous, .paddingBottom)
                        : 0
                    let prevMarginBottom: CGFloat = isBlock(previous)
                        ? blockStyle(previous).box.margin.bottom
                        : 0
                    setField(
                        .y,
                        prevY + prevHeight + prevPadBottom + prevMarginBottom * blockZoom + ownTop + padTop,
                        for: id
                    )
                } else {
                    setField(.y, y(parentID(of: id)!), for: id)
                    setField(.y, y(id) + ownTop + padTop, for: id)
                }
            }

            if let el = domView(id).element, el.attributes["id"] == "toc" {
                setField(.y, y(id) + VSTEP, for: id)
            }

            let mode: String = profiler.measure("layout.mode", { layoutMode(id) })
            if mode == "block" {
                profiler.count("layout.mode.block")
                if isDirty(.children, at: id) {
                    setChildrenField(rebuildBlockChildren(id), of: id)
                } else if !blockData(id).changes.childChanges.isEmpty {
                    let changes: [BlockChildChange] = blockData(id).changes.childChanges
                    var data: BlockData = blockData(id)
                    data.changes.childChanges.removeAll()
                    setKind(.block(data), at: id)
                    if let changed: [LayoutID] = applyBlockChanges(id, changes) {
                        countChildChanges(changes)
                        setChildrenField(changed, of: id)
                    } else {
                        setChildrenField(rebuildBlockChildren(id), of: id)
                    }
                }

                if isDirty(.inlineContent, at: id) {
                    let revision: UInt64 = node(id).state.fields.inlineText.inlineContent + 1
                    setInlineContentClean(revision, for: id)
                    var data: BlockData = blockData(id)
                    data.content.inlineObjects.removeAll(keepingCapacity: true)
                    data.content.inlineLinePlan = nil
                    setKind(.block(data), at: id)
                }
            } else {
                profiler.count("layout.mode.inline")
                let inlineContentChanged: Bool = isDirty(.inlineContent, at: id)
                    || !blockData(id).changes.childChanges.isEmpty
                var data: BlockData = blockData(id)
                data.changes.childChanges.removeAll()
                setKind(.block(data), at: id)
                _ = zoom(id)
                
                if inlineContentChanged {
                    profiler.measure("layout.inline.refresh", { refreshInlineItems(id) })
                }
                let plan: [[Int]]? = inlineTextLinePlan(id)
                let shouldPlace: Bool = inlineContentChanged
                    || plan == nil
                    || plan != blockData(id).content.inlineLinePlan
                if shouldPlace {
                    profiler.measure("layout.inline.place", { placeInlineItems(id) })
                } else {
                    setChildrenField(childrenIDs(of: id), of: id)
                }
                var updated: BlockData = blockData(id)
                updated.content.inlineLinePlan = plan
                setKind(.block(updated), at: id)
            }
        }

        for child in childrenIDs(of: id) { layout(child) }

        setHeightInputs(id)
        let heightChildren: [LayoutID] = childrenIDs(of: id)
        let sumHeight: Double = profiler.measure("layout.height", {
            heightChildren.reduce(0) { total, childID in
                let position: LayoutStyle.Position = domView(childID).style.computed.layout.position.kind
                if position == .absolute { return total }
                var h: CGFloat = height(childID)
                if isBlock(childID) {
                    let childStyle: BlockStyle = blockStyle(childID)
                    let childZoom: CGFloat = zoom(childID)
                    h += (childStyle.box.padding.top + childStyle.box.padding.bottom) * childZoom
                    h += (childStyle.box.margin.top + childStyle.box.margin.bottom) * childZoom
                }
                return total + h
            }
        })

        var scroll: BlockScroll = blockData(id).scroll
        if let h: CGFloat = domView(id).style.computed.box.size.height {
            scroll.contentHeight = sumHeight
            let styleHeightZoom: CGFloat = zoom(id)
            setField(.height, h * styleHeightZoom, for: id)
        } else {
            scroll.contentHeight = sumHeight
            setField(.height, sumHeight, for: id)
        }

        if let el = domView(id).element, el.attributes["id"] == "toc" {
            setField(.height, height(id) + VSTEP, for: id)
        }

        if style.flags.overflowScroll, domView(id).element != nil {
            let maxScroll: CGFloat = max(0, scroll.contentHeight - height(id))
            scroll.offset = min(inputs.scrollOffset(domID(of: id)), maxScroll)
        }
        var data: BlockData = blockData(id)
        data.scroll = scroll
        setKind(.block(data), at: id)
    }

    private func layoutMode(_ id: LayoutID) -> String {
        if !blockExtraNodes(id).isEmpty { return "inline" }
        if domView(id).text != nil { return "inline" }
        let hasBlockChild: Bool = domView(id).children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if hasBlockChild { return "block" }
        if let el = domView(id).element {
            return (el.children.isEmpty && el.tag != "input" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas") ? "block" : "inline"
        }
        return "inline"
    }

    mutating private func rebuildBlockChildren(_ id: LayoutID) -> [LayoutID] {
        profiler.count("layout.children.rebuilt")
        var data: BlockData = blockData(id)
        data.changes.childChanges.removeAll()
        setKind(.block(data), at: id)
        var state: BlockChildBuild = BlockChildBuild()
        consumeBlockChildren(id, domView(id).children, state: &state)
        finishBlockChildren(id, &state)
        return state.built
    }

    mutating private func appendBlockChildren(
        _ id: LayoutID,
        _ nodes: [LayoutDOMView],
        to current: [LayoutID]
    ) -> [LayoutID]? {
        guard blockExtraNodes(id).isEmpty,
            current.allSatisfy({ isBlock($0) })
        else {
            return nil
        }
        if let lastID: LayoutID = current.last {
            if blockExtraNodes(lastID).isEmpty, domView(lastID).element?.tag == "h6" {
                return nil
            }
        }
        guard let first: LayoutDOMView = firstVisibleChild(in: nodes) else {
            return nil
        }

        var state: BlockChildBuild = BlockChildBuild(
            built: current,
            previous: lastFlowChild(id, in: current)
        )
        let startsInline: Bool = first.style.computed.layout.display != .block
        if startsInline, let lastID: LayoutID = state.built.last {
            let extras: [LayoutDOMView] = blockExtraNodes(lastID)
            if !extras.isEmpty,
                extras.allSatisfy({ $0.style.computed.layout.display != .block })
            {
                state.built.removeLast()
                state.inlineRun = extras
                state.previous = previousID(of: lastID)
            }
        }

        consumeBlockChildren(id, nodes, state: &state)
        finishBlockChildren(id, &state)
        return state.built
    }

    mutating private func applyBlockChanges(
        _ id: LayoutID,
        _ changes: [BlockChildChange]
    ) -> [LayoutID]? {
        var current: [LayoutID] = childrenIDs(of: id)
        for change in changes {
            switch change {
            case .append(let nodes):
                let views: [LayoutDOMView] = nodes.map({ domView($0) })
                guard let next: [LayoutID] = appendBlockChildren(id, views, to: current) else {
                    return nil
                }
                current = next
            case .insert(let nodes, let reference):
                let views: [LayoutDOMView] = nodes.map({ domView($0) })
                guard let next: [LayoutID] = insertBlockChildren(
                    id,
                    views,
                    before: domView(reference),
                    in: current
                ) else {
                    return nil
                }
                current = next
            }
        }
        return current
    }

    private func countChildChanges(_ changes: [BlockChildChange]) {
        for change in changes {
            switch change {
            case .append(_):
                profiler.count("layout.children.appended")
            case .insert(_, _):
                profiler.count("layout.children.inserted")
            }
        }
    }

    mutating private func insertBlockChildren(
        _ id: LayoutID,
        _ nodes: [LayoutDOMView],
        before reference: LayoutDOMView,
        in current: [LayoutID]
    ) -> [LayoutID]? {
        guard blockExtraNodes(id).isEmpty,
            current.allSatisfy({ isBlock($0) })
        else {
            return nil
        }
        guard let index: Int = blockChildIndex(of: reference, in: current) else {
            return nil
        }
        guard !nodes.contains(where: { $0.element?.tag == "h6" }) else {
            return nil
        }
        if index > 0, isRunIn(current[index - 1]) {
            return nil
        }
        if isRunIn(current[index]) {
            return nil
        }
        guard let first: LayoutDOMView = firstVisibleChild(in: nodes) else {
            return current
        }

        let startsInline: Bool = first.style.computed.layout.display != .block
        if startsInline, index > 0 {
            let previous: LayoutID = current[index - 1]
            if !blockExtraNodes(previous).isEmpty {
                return nil
            }
        }

        let prefix: [LayoutID] = Array(current[..<index])
        var state: BlockChildBuild = BlockChildBuild(
            built: prefix,
            previous: lastFlowChild(id, in: prefix)
        )
        consumeBlockChildren(id, nodes, state: &state)
        finishBlockChildren(id, &state)

        var previous: LayoutID? = state.previous
        for id in current[index...] {
            setBlockPrevious(id, previous)
            let isFlow: Bool = !blockExtraNodes(id).isEmpty
                || domView(id).style.computed.layout.position.kind != .absolute
            if isFlow { previous = id }
        }

        var result: [LayoutID] = state.built
        result.append(contentsOf: current[index...])
        return result
    }

    private func blockChildIndex(
        of reference: LayoutDOMView,
        in current: [LayoutID]
    ) -> Int? {
        for (index, id) in current.enumerated() {
            let extras: [LayoutDOMView] = blockExtraNodes(id)
            if domID(of: id) == reference.id, extras.isEmpty {
                return index
            }
            if extras.contains(where: { $0.id == reference.id }) {
                return nil
            }
        }
        return nil
    }

    private func isRunIn(_ id: LayoutID) -> Bool {
        let first: LayoutDOMView = blockExtraNodes(id).first ?? domView(id)
        return first.element?.tag == "h6"
    }

    private func firstVisibleChild(in nodes: [LayoutDOMView]) -> LayoutDOMView? {
        return nodes.first(where: { child in
            guard let el = child.element else { return true }
            return !LayoutTree.hiddenElements.contains(el.tag)
        })
    }

    private func lastFlowChild(_ id: LayoutID, in children: [LayoutID]) -> LayoutID? {
        for id in children.reversed() {
            if isBlock(id), !blockExtraNodes(id).isEmpty {
                return id
            }
            if domView(id).style.computed.layout.position.kind != .absolute {
                return id
            }
        }
        return nil
    }

    mutating private func consumeBlockChildren(
        _ id: LayoutID,
        _ nodes: [LayoutDOMView],
        state: inout BlockChildBuild
    ) {
        for child in nodes {
            if let el = child.element, LayoutTree.hiddenElements.contains(el.tag) {
                continue
            }
            let isBlock: Bool = child.style.computed.layout.display == .block
            if isBlock {
                if let el = child.element, el.tag == "h6" {
                    flushInlineRun(id, &state)
                    state.pendingRunIn = el
                } else {
                    flushInlineRun(id, &state)
                    if let runIn: LayoutElementView = state.pendingRunIn {
                        let run: [NodeID] = [runIn.ref.id, child.id]
                        let next: LayoutID = makeAnonymousBlock(
                            extraNodes: run,
                            parent: id,
                            previous: state.previous
                        )
                        state.built.append(next)
                        state.previous = next
                        state.pendingRunIn = nil
                    } else {
                        let next: LayoutID = makeBlock(
                            dom: child.id,
                            parent: id,
                            previous: state.previous
                        )
                        state.built.append(next)
                        if child.style.computed.layout.position.kind != .absolute {
                            state.previous = next
                        }
                    }
                }
            } else {
                state.inlineRun.append(child)
            }
        }
    }

    mutating private func flushInlineRun(_ id: LayoutID, _ state: inout BlockChildBuild) {
        guard !state.inlineRun.isEmpty else { return }
        let run: [LayoutDOMView] = state.inlineRun
        let anon: LayoutID = makeAnonymousBlock(
            extraNodes: run.map({ $0.id }),
            parent: id,
            previous: state.previous
        )
        state.built.append(anon)
        state.previous = anon
        state.inlineRun = []
    }

    mutating private func finishBlockChildren(_ id: LayoutID, _ state: inout BlockChildBuild) {
        flushInlineRun(id, &state)
        if let runIn: LayoutElementView = state.pendingRunIn {
            let next: LayoutID = makeBlock(
                dom: runIn.ref.id,
                parent: id,
                previous: state.previous
            )
            state.built.append(next)
        }
    }

    // MARK: - Padding

    private func paddingValue(_ id: LayoutID, _ side: StyleProperty) -> CGFloat {
        let insets: EdgeInsets = domView(id).style.computed.box.spacing.padding
        switch side {
        case .paddingTop: return insets.top
        case .paddingRight: return insets.right
        case .paddingBottom: return insets.bottom
        case .paddingLeft: return insets.left
        default: return 0
        }
    }

    func padding(_ id: LayoutID, _ side: StyleProperty) -> CGFloat {
        guard blockExtraNodes(id).isEmpty else { return 0 }
        return max(0, paddingValue(id, side) * zoom(id))
    }

    private func paintedPadding(_ id: LayoutID, _ side: StyleProperty) -> CGFloat {
        guard blockExtraNodes(id).isEmpty else { return 0 }
        return max(0, paddingValue(id, side) * zoom(id))
    }

    func paddingVertical(_ id: LayoutID) -> CGFloat {
        return padding(id, .paddingTop) + padding(id, .paddingBottom)
    }

    func boxHeight(_ id: LayoutID) -> CGFloat {
        return height(id) + paddingVertical(id)
    }

    // MARK: - Inline items

    mutating private func placeInlineItems(_ id: LayoutID) {
        let items: [InlineItem] = blockData(id).content.inlineItems
        var placement: InlinePlacement = InlinePlacement(parent: id)
        placement.start(in: &self)
        for (index, item) in items.enumerated() {
            switch item {
            case .lineBreak:
                placement.endLine(in: &self)
            case .text(let text):
                placeText(id, text, index: index, into: &placement)
            case .embed(let element):
                placeEmbed(id, element, index: index, into: &placement)
            }
        }
        placement.finish(in: &self)
        setChildrenField(placement.lines, of: id)
        profiler.count("layout.lines.total", by: placement.lines.count)
    }

    mutating private func refreshInlineItems(_ id: LayoutID) {
        let leaves: [LayoutDOMView] = inlineLeaves(id)
        var items: [InlineItem] = []
        for leaf in leaves {
            items.append(contentsOf: makeItems(id, for: leaf))
        }
        var data: BlockData = blockData(id)
        data.content.inlineItems = items
        data.content.inlineObjects.removeAll(keepingCapacity: true)
        data.content.inlineLinePlan = nil
        setKind(.block(data), at: id)
        let revision: UInt64 = node(id).state.fields.inlineText.inlineContent + 1
        setInlineContent(revision, for: id)
    }

    private func collectLeaves(_ n: LayoutDOMView, into leaves: inout [LayoutDOMView]) {
        if n.text != nil {
            leaves.append(n)
            return
        }
        guard let el = n.element else { return }
        if el.tag == "br" || isEmbed(el) {
            leaves.append(n)
            return
        }
        for child in n.children { collectLeaves(child, into: &leaves) }
    }

    private func isEmbed(_ el: LayoutElementView) -> Bool {
        el.tag == "input" || el.tag == "button" || el.tag == "img"
        || el.tag == "iframe" || el.tag == "canvas"
    }

    private func makeItems(_ id: LayoutID, for leaf: LayoutDOMView) -> [InlineItem] {
        var items: [InlineItem] = []
        if let text = leaf.text {
            addTextNode(id, text, into: &items)
        } else if let el = leaf.element {
            if el.tag == "br" {
                items.append(.lineBreak)
            } else {
                items.append(.embed(el))
            }
        }
        return items
    }

    private func addTextNode(
        _ id: LayoutID,
        _ textNode: LayoutTextView,
        into items: inout [InlineItem]
    ) {
        let owner: NodeID = inputs.inheritedStyleOwner(textNode.ref.id)
        let mode: WhiteSpaceMode = inputs.style(owner).text.whiteSpace
        let zoom: CGFloat = zoom(id)
        let font: BrowserFont = fontFor(textNode.ref.id, zoom: zoom)
        let run: InlineTextRun = InlineTextRun(
            node: textNode.ref,
            font: font,
            whiteSpace: mode,
            isAbbr: isInsideAbbr(textNode.ref),
        )
        if mode.keepsNewlines {
            let segments: [String] = textNode.text.components(separatedBy: "\n")
            for (i, segment) in segments.enumerated() {
                if i > 0 { items.append(.lineBreak) }
                addSegment(id, text: segment, run: run, into: &items)
            }
        } else {
            addSegment(id, text: textNode.text, run: run, into: &items)
        }
    }

    private func addSegment(
        _ id: LayoutID,
        text: String,
        run: InlineTextRun,
        into items: inout [InlineItem]
    ) {
        if run.whiteSpace.keepSpaces {
            if !text.isEmpty { addWord(id, text, run: run, into: &items) }
        } else {
            for word in text.split(whereSeparator: { $0.isWhitespace }) {
                addWord(id, String(word), run: run, into: &items)
            }
        }
    }

    private func addWord(
        _ id: LayoutID,
        _ word: String,
        run: InlineTextRun,
        into items: inout [InlineItem]
    ) {
        profiler.count("text.words")

        if run.isAbbr && word.contains(where: { $0.isLowercase }) {
            addAbbrWord(id, run: run, word: word, into: &items)
            return
        }
        items.append(.text(InlineTextItem(run: run, word: word, display: nil)))
    }

    mutating private func placeEmbed(
        _ id: LayoutID,
        _ element: LayoutElementView,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        if placement.currentLine != nil {
            var data: LineData = lineData(placement.currentLine!)
            data.content.hasEmbed = true
            setKind(.line(data), at: placement.currentLine!)
        }
        switch element.tag {
        case "input": addInput(id, element, index: index, into: &placement)
        case "button": addButton(id, element, index: index, into: &placement)
        case "img": addImage(id, element, index: index, into: &placement)
        case "iframe": addIframe(id, element, index: index, into: &placement)
        case "canvas": addCanvas(id, element, index: index, into: &placement)
        default: break
        }
    }

    mutating private func placeText(
        _ id: LayoutID,
        _ item: InlineTextItem,
        index: Int?,
        into placement: inout InlinePlacement
    ) {
        let font: BrowserFont = item.fontOverride ?? item.run.font
        let measured: CGFloat = item.measuredWidth ?? font.measure(item.display ?? item.word)
        let w: CGFloat = measured + font.spaceWidth
        if placement.cursorX + w > width(id) && item.run.whiteSpace.wraps {
            if item.word.contains("\u{00AD}") {
                let parts: [String] = item.word.components(separatedBy: "\u{00AD}")
                var chunk: String = ""
                var breakIdx: Int = -1
                for (i, part) in parts.dropLast().enumerated() {
                    let candidate: String = chunk + part + "-"
                    if placement.cursorX + font.measure(candidate) <= width(id) {
                        chunk = chunk + part
                        breakIdx = i
                    }
                }
                if breakIdx >= 0 {
                    appendToLine(id, clone(item, word: chunk + "-"), index: nil, into: &placement)
                    placement.endLine(in: &self)
                    placeText(
                        id,
                        clone(item, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}")),
                        index: nil,
                        into: &placement
                    )
                    return
                }
            }
            placement.endLine(in: &self)
        }

        appendToLine(id, item, index: index, into: &placement)
        placement.cursorX += w
    }

    mutating private func appendToLine(
        _ id: LayoutID,
        _ item: InlineTextItem,
        index: Int?,
        into placement: inout InlinePlacement
    ) {
        let font: BrowserFont = item.fontOverride ?? item.run.font
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let text: LayoutID
        if let index,
            let cached: LayoutID = cachedText(id, at: index, node: item.run.node, word: item.word)
        {
            text = cached
            attachText(cached, to: lineID, previous: previous)
        } else {
            text = makeText(
                TextData(
                    word: item.word,
                    display: item.display,
                    fontOverride: item.fontOverride,
                    metrics: TextMetrics(width: 0, whiteSpace: item.run.whiteSpace)
                ),
                dom: item.run.node.id,
                parent: lineID,
                previous: previous
            )
            setFont(font, for: text)
            if let index {
                var data: BlockData = blockData(id)
                data.content.inlineObjects[index] = text
                setKind(.block(data), at: id)
            }
        }
        placement.append(text)
    }

    private func clone(_ item: InlineTextItem, word: String) -> InlineTextItem {
        InlineTextItem(
            run: item.run,
            word: word,
            display: nil,
            fontOverride: item.fontOverride
        )
    }

    mutating private func addInput(
        _ id: LayoutID,
        _ node: LayoutElementView,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        if node.attributes["type"] == "hidden" { return }

        let available: CGFloat = width(id)
        let zoom: CGFloat = zoom(id)
        let font: BrowserFont = fontFor(node.ref.id, zoom: zoom)
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : inputWidthPx * zoom
        if placement.cursorX + w > available { placement.endLine(in: &self) }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let input: LayoutID
        if let cached: LayoutID = cachedEmbed(id, .input, at: index, node: node) {
            input = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            input = makeEmbed(dom: node.ref.id, data: .input, parent: lineID, previous: previous)
            var data: BlockData = blockData(id)
            data.content.inlineObjects[index] = input
            setKind(.block(data), at: id)
        }
        placement.append(input)

        placement.cursorX += w + font.spaceWidth
    }

    mutating private func addButton(
        _ id: LayoutID,
        _ node: LayoutElementView,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = width(id)
        let zoom: CGFloat = zoom(id)
        let w: CGFloat = inputWidthPx * zoom
        if placement.cursorX + w > available { placement.endLine(in: &self) }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let button: LayoutID
        if let cached: LayoutID = cachedEmbed(id, .button, at: index, node: node) {
            button = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            button = makeEmbed(
                dom: node.ref.id,
                data: .button(ButtonData(cursorX: 0)),
                parent: lineID,
                previous: previous
            )
            var data: BlockData = blockData(id)
            data.content.inlineObjects[index] = button
            setKind(.block(data), at: id)
        }
        placement.append(button)
        let font: BrowserFont = fontFor(node.ref.id, zoom: zoom)
        placement.cursorX += w + font.spaceWidth
    }

    mutating private func addImage(
        _ id: LayoutID,
        _ node: LayoutElementView,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = width(id)
        let zoom: CGFloat = zoom(id)
        let w: CGFloat = imageUsedWidth(EmbedMetrics(node), available: available, zoom: zoom)
        if placement.cursorX + w > available { placement.endLine(in: &self) }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let image: LayoutID
        if let cached: LayoutID = cachedEmbed(id, .image, at: index, node: node) {
            image = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            image = makeEmbed(
                dom: node.ref.id,
                data: .image(ImageData(imageHeight: 0)),
                parent: lineID,
                previous: previous
            )
            var data: BlockData = blockData(id)
            data.content.inlineObjects[index] = image
            setKind(.block(data), at: id)
        }
        placement.append(image)

        let font: BrowserFont = fontFor(node.ref.id, zoom: zoom)
        placement.cursorX += w + font.spaceWidth
    }

    mutating private func addIframe(
        _ id: LayoutID,
        _ node: LayoutElementView,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = width(id)
        let zoom: CGFloat = zoom(id)
        let w: CGFloat = iframeDisplaySize(EmbedMetrics(node)).width * zoom
        if placement.cursorX + w > available { placement.endLine(in: &self) }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let iframe: LayoutID
        if let cached: LayoutID = cachedEmbed(id, .iframe, at: index, node: node) {
            iframe = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            iframe = makeEmbed(
                dom: node.ref.id,
                data: .iframe,
                parent: lineID,
                previous: previous
            )
            var data: BlockData = blockData(id)
            data.content.inlineObjects[index] = iframe
            setKind(.block(data), at: id)
        }
        placement.append(iframe)

        let font: BrowserFont = fontFor(node.ref.id, zoom: zoom)
        placement.cursorX += w + font.spaceWidth
    }

    mutating private func addCanvas(
        _ id: LayoutID,
        _ node: LayoutElementView,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = width(id)
        let zoom: CGFloat = zoom(id)
        let w: CGFloat = canvasContentSize(attributes: node.attributes).width * zoom
        if placement.cursorX + w > available { placement.endLine(in: &self) }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let canvas: LayoutID
        if let cached: LayoutID = cachedEmbed(id, .canvas, at: index, node: node) {
            canvas = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            canvas = makeEmbed(
                dom: node.ref.id,
                data: .canvas,
                parent: lineID,
                previous: previous
            )
            var data: BlockData = blockData(id)
            data.content.inlineObjects[index] = canvas
            setKind(.block(data), at: id)
        }
        placement.append(canvas)

        let font: BrowserFont = fontFor(node.ref.id, zoom: zoom)
        placement.cursorX += w + font.spaceWidth
    }

    private func isInsideAbbr(_ node: LayoutDOMView) -> Bool {
        var current: LayoutDOMView? = node.parent
        while let c = current {
            if let el = c.element, el.tag == "abbr" { return true }
            current = c.parent
        }
        return false
    }

    private func addAbbrWord(
        _ id: LayoutID,
        run: InlineTextRun,
        word: String,
        into items: inout [InlineItem]
    ) {
        var runs: [(String, Bool)] = []
        for ch in word {
            let isLower: Bool = ch.isLowercase
            if runs.last?.1 == isLower {
                runs[runs.count - 1].0.append(ch)
            } else {
                runs.append((String(ch), isLower))
            }
        }

        let node: LayoutDOMView = run.node
        let owner: LayoutDOMView = node.inheritedStyleOwner
        let fontSpec: TextStyle.Font = owner.style.computed.text.font
        let weight: String = fontSpec.weight.cssValue
        let styleStr: String = fontSpec.style.browserFontStyle
        let sizeInt: Int = Int(fontSpec.size)
        let smallSize: Int = Int(Double(sizeInt))
        let family: String = fontSpec.family

        for (text, isLower) in runs {
            let displayText: String = isLower ? text.uppercased() : text
            let font: BrowserFont =
                isLower
                ? getFont(size: smallSize, weight: "bold", style: styleStr, family: family)
                : getFont(size: sizeInt, weight: weight, style: styleStr, family: family)
            items.append(.text(InlineTextItem(run: run, word: text, display: displayText, fontOverride: font)))
        }
    }

    private func cachedText(
        _ id: LayoutID,
        at index: Int,
        node: LayoutDOMView,
        word: String
    ) -> LayoutID? {
        guard let id: LayoutID = blockData(id).content.inlineObjects[index] else { return nil }
        guard contains(id) else { return nil }
        guard isText(id),
            domID(of: id) == node.id,
            textData(id).word == word
        else { return nil }
        return id
    }

    private func cachedEmbed(
        _ id: LayoutID,
        _ kind: EmbedMatch,
        at index: Int,
        node: LayoutElementView
    ) -> LayoutID? {
        guard let id: LayoutID = blockData(id).content.inlineObjects[index] else { return nil }
        guard contains(id) else { return nil }
        guard isEmbed(id),
            domID(of: id) == node.ref.id,
            kind.matches(embedData(id))
        else { return nil }
        return id
    }

    // MARK: - Paint

    func blockSelfRect(_ id: LayoutID) -> Rect {
        let top: CGFloat = paintedPadding(id, .paddingTop)
        let right: CGFloat = paintedPadding(id, .paddingRight)
        let bottom: CGFloat = paintedPadding(id, .paddingBottom)
        let left: CGFloat = paintedPadding(id, .paddingLeft)
        return Rect(
            left: x(id) - left,
            top: y(id) - top,
            right: x(id) + width(id) + right,
            bottom: y(id) + height(id) + bottom
        )
    }

    private func borderPaintRect(_ id: LayoutID) -> Rect {
        let rect: Rect = blockSelfRect(id)
        let width: CGFloat = domView(id).style.computed.box.decoration.border.width
        guard width > 0 else { return rect }
        let half: CGFloat = width / 2
        return Rect(
            left: rect.left - half,
            top: rect.top - half,
            right: rect.right + half,
            bottom: rect.bottom + half
        )
    }

    

    func blockPaintCaret(_ id: LayoutID, into items: inout [DisplayOp]) {
        guard let el = domView(id).element, el.isFocused,
            el.attributes["contenteditable"] != nil
        else { return }
        if let last: LayoutID = lastTextLayout(id) {
            items.append(drawCursor(
                origin: Point(x: x(last), y: y(last)),
                height: height(last),
                offset: textTextWidth(last)
            ))
        } else {
            items.append(drawCursor(origin: Point(x: x(id), y: y(id)), height: height(id), offset: 0))
        }
    }

    func blockPaintScrollbar(_ id: LayoutID) -> [DisplayOp] {
        let scroll: BlockScroll = blockData(id).scroll
        guard domView(id).style.computed.layout.overflow == .scroll,
            scroll.contentHeight > height(id)
        else { return [] }
        let barWidth: CGFloat = 8
        let ratio: CGFloat = height(id) / scroll.contentHeight
        let barHeight: CGFloat = ratio * height(id)
        let barTop: CGFloat = y(id) + (scroll.offset / scroll.contentHeight) * height(id)
        let barRect: Rect = Rect(
            left: x(id) + width(id) - barWidth, top: barTop,
            right: x(id) + width(id), bottom: barTop + barHeight)
        return [.rect(rect: barRect, color: BrowserColor(cssName: inputs.forcedColors(domID(of: id)) ? ForcedColor.canvasText : "gray"))]
    }

    func blockShouldPaint(_ id: LayoutID) -> Bool {
        if domView(id).text != nil { return true }
        guard let el = domView(id).element else { return true }
        return el.tag != "input" && el.tag != "button" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas"
    }

    mutating func blockStyle(_ id: LayoutID) -> BlockStyle {
        let revision: UInt64 = domView(id).style.revision
        let paint: BlockPaint = blockData(id).paint
        if let cachedStyle = paint.style, paint.styleRevision == revision {
            profiler.count("layout.block.style.cache.hit")
            return cachedStyle
        }
        profiler.count("layout.block.style.cache.miss")
        let style: BlockStyle = BlockStyle(style: domView(id).style.computed)
        var data: BlockData = blockData(id)
        data.paint.style = style
        data.paint.styleRevision = revision
        setKind(.block(data), at: id)
        return style
    }

    // MARK: - Cursor

    private func lastTextLayout(_ id: LayoutID) -> LayoutID? {
        for child in childrenIDs(of: id).reversed() {
            if isText(child) { return child }
            if let nested: LayoutID = lastTextLayout(child) { return nested }
        }
        return nil
    }

    // MARK: - Scroll

    func blockScrollOffset(_ id: LayoutID) -> CGFloat {
        return blockData(id).scroll.offset
    }

    mutating func setBlockScrollOffset(_ id: LayoutID, _ value: CGFloat) {
        var data: BlockData = blockData(id)
        data.scroll.offset = value
        setKind(.block(data), at: id)
    }

    func blockContentHeight(_ id: LayoutID) -> CGFloat {
        return blockData(id).scroll.contentHeight
    }
}

// MARK: - Embed match

enum EmbedMatch {
    case image
    case input
    case button
    case iframe
    case canvas

    func matches(_ data: EmbedData) -> Bool {
        switch (self, data) {
        case (.image, .image), (.input, .input), (.button, .button),
            (.iframe, .iframe), (.canvas, .canvas):
            return true
        default:
            return false
        }
    }
}

// MARK: - Block child build

// Mutable cursor for one pass of the block child builder.
private struct BlockChildBuild {
    var built: [LayoutID] = []
    var previous: LayoutID?
    var inlineRun: [LayoutDOMView] = []
    var pendingRunIn: LayoutElementView?
}

// MARK: - Inline placement

private struct InlinePlacementContext {
    let parent: LayoutID
}

private struct InlinePlacementState {
    var lines: [LayoutID] = []
    var currentLine: LayoutID? = nil
    var children: [LayoutID] = []
    var cursorX: CGFloat = 0
}

struct InlinePlacement {
    private let context: InlinePlacementContext
    private var state: InlinePlacementState = InlinePlacementState()

    init(parent: LayoutID) {
        self.context = InlinePlacementContext(parent: parent)
    }

    var lines: [LayoutID] { state.lines }
    var currentLine: LayoutID? { state.currentLine }
    var children: [LayoutID] { state.children }
    var cursorX: CGFloat {
        get { state.cursorX }
        set { state.cursorX = newValue }
    }

    mutating func start(in tree: inout LayoutTree) {
        let previous: LayoutID? = state.lines.last
        state.currentLine = tree.makeLine(
            dom: tree.node(context.parent).dom,
            parent: context.parent,
            previous: previous
        )
        state.children = []
        state.cursorX = 0
    }

    mutating func endLine(in tree: inout LayoutTree) {
        guard let line: LayoutID = state.currentLine else { return }
        tree.setChildrenField(state.children, of: line)
        state.lines.append(line)
        start(in: &tree)
    }

    mutating func finish(in tree: inout LayoutTree) {
        guard let line: LayoutID = state.currentLine else { return }
        tree.setChildrenField(state.children, of: line)
        state.lines.append(line)
        state.currentLine = nil
        state.children = []
    }

    mutating func append(_ child: LayoutID) {
        state.children.append(child)
    }
}

