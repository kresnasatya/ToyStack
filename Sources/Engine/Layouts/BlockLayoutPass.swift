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

    func blockChildrenInputs(_ id: LayoutID) -> [FieldKey] {
        guard layoutMode(id) == .block else { return [] }
        var inputs: [FieldKey] = []
        for child in domView(id).children {
            inputs.append(.style(child.id, .display))
            inputs.append(.style(child.id, .position))
        }
        return inputs
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
        let style: BlockStyle = profiler.measure("layout.blockStyle", { blockStyle(id) })
        var skipInlineChildren: Bool = false
        let frameWasClean: Bool = !isDirty(.x, at: id) && !isDirty(.y, at: id)
        let oldFrameX: CGFloat = frameWasClean ? x(id) : 0
        let oldFrameY: CGFloat = frameWasClean ? y(id) : 0
        let widthWasDirty: Bool = isDirty(.width, at: id)
        let geometryDirty: Bool = isDirty(.zoom, at: id) || isDirty(.x, at: id)
            || isDirty(.y, at: id) || widthWasDirty
        profiler.measure("layout.visit") {
            profiler.count("layout.rebuilt")
            if geometryDirty {
            profiler.measure("layout.visit.geometry", {
            let zoomValue: CGFloat = resolvedZoom(id)
            let isAbsolute: Bool = style.position == .absolute
            let parent: LayoutID = parentID(of: id)!

            let parentX: CGFloat = x(parent)
            let padLeft: CGFloat = blockExtraNodes(id).isEmpty
                ? style.box.padding.left * zoomValue
                : 0
            var frameX: CGFloat
            if isAbsolute, let l = style.flags.left {
                frameX = l * zoomValue + padLeft
            } else {
                frameX = parentX + padLeft
            }

            let parentWidth: CGFloat = width(parent)
            let padHorizontal: CGFloat = blockExtraNodes(id).isEmpty
                ? (style.box.padding.left + style.box.padding.right) * zoomValue
                : 0
            var frameWidth: CGFloat
            if let w = style.box.width {
                frameWidth = w * zoomValue
            } else {
                frameWidth = max(0, parentWidth - padHorizontal)
            }

            let element = domView(id).element
            if element?.tag == "li" {
                frameX += liIndent
                frameWidth -= liIndent
            }

            var frameY: CGFloat
            if isAbsolute, let t = style.flags.top {
                let padTop: CGFloat = blockExtraNodes(id).isEmpty
                    ? style.box.padding.left * zoomValue
                    : 0
                frameY = t * zoomValue + padTop
            } else {
                let ownTop: CGFloat = style.box.margin.top * zoomValue
                let padTop: CGFloat = style.box.padding.top * zoomValue
                if let previous: LayoutID = blockPrevious(id) {
                    let prevY: CGFloat = y(previous)
                    let prevHeight: CGFloat = height(previous)
                    let prevPadBottom: CGFloat = isBlock(previous)
                        ? padding(previous, .paddingBottom)
                        : 0
                    let prevMarginBottom: CGFloat = isBlock(previous)
                        ? blockStyle(previous).box.margin.bottom
                        : 0
                    frameY = prevY + prevHeight + prevPadBottom
                        + prevMarginBottom * zoomValue + ownTop + padTop
                } else {
                    frameY = y(parent) + ownTop + padTop
                }
            }

            if element?.attributes["id"] == "toc" {
                frameY += VSTEP
            }

            setFrame(
                (zoom: zoomValue, x: frameX, y: frameY, width: frameWidth),
                for: id
            )
            })
            }
            let frameMoved: Bool = geometryDirty
                && (!frameWasClean || x(id) != oldFrameX || y(id) != oldFrameY)
            let widthChanged: Bool = geometryDirty && widthWasDirty

            let mode: LayoutMode = profiler.measure("layout.mode", { layoutMode(id) })
            if mode == .block {
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
                
                var preservedItems: Bool = false
                if inlineContentChanged {
                    let preserveObjects: Bool = canRefreshFontsOnly(id)
                    profiler.measure("layout.inline.refresh", {
                        preservedItems = refreshInlineItems(id, preservingObjects: preserveObjects)
                    })
                }
                let oldPlan: [[Int]]? = blockData(id).content.inlineLinePlan
                let plan: [[Int]]? = profiler.measure("layout.inline.plan", {
                    inlineTextLinePlan(id)
                })
                let shouldPlace: Bool = inlineContentChanged
                    || plan == nil
                    || plan != oldPlan
                let canReusePlan: Bool = !inlineContentChanged || preservedItems
                if !shouldPlace, widthChanged, !frameMoved,
                    !isDirty(.height, at: id),
                    canSkipInlineChildren(id)
                {
                    updateInlineLineFrames(id)
                    skipInlineChildren = true
                }
                if shouldPlace {
                    if canReusePlan, let plan, let oldPlan {
                        profiler.measure("layout.inline.place", {
                            placeInlineItems(
                                id,
                                plan: plan,
                                oldPlan: oldPlan,
                                refreshMetrics: preservedItems
                            )
                        })
                    } else {
                        profiler.measure("layout.inline.place", { placeInlineItems(id) })
                    }
                } else {
                    setChildrenField(childrenIDs(of: id), of: id)
                }
                var updated: BlockData = blockData(id)
                updated.content.inlineLinePlan = plan
                setKind(.block(updated), at: id)
            }
        }

        var measuredHeight: CGFloat? = nil
        if !skipInlineChildren {
            profiler.measure("layout.visit.children", {
                for child in childrenIDs(of: id) { layout(child) }
            })

            setHeightInputs(id)
            let heightChildren: [LayoutID] = childrenIDs(of: id)
            measuredHeight = profiler.measure("layout.height", {
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
        } else {
            profiler.count("layout.inline.children.skipped")
        }

        var scroll: BlockScroll = blockData(id).scroll
        if let sumHeight = measuredHeight {
            scroll.contentHeight = sumHeight
            if let h: CGFloat = domView(id).style.computed.box.size.height {
                let styleHeightZoom: CGFloat = zoom(id)
                setField(.height, h * styleHeightZoom, for: id)
            } else {
                setField(.height, sumHeight, for: id)
            }
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

    private enum LayoutMode {
        case block
        case inline
    }

    private func layoutMode(_ id: LayoutID) -> LayoutMode {
        if !blockExtraNodes(id).isEmpty { return .inline }
        if domView(id).text != nil { return .inline }
        let hasBlockChild: Bool = domView(id).children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if hasBlockChild { return .block }
        if let el = domView(id).element {
            return (el.children.isEmpty && el.tag != "input" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas") ? .block : .inline
        }
        return .inline
    }

    /// A width-only change that keeps the break plan leaves line contents and
    /// heights intact. Left-to-right text with no embeds only needs new line
    /// widths, so its line children do not have to be visited again.
    private func canSkipInlineChildren(_ id: LayoutID) -> Bool {
        guard inputs.style(domID(of: id)).text.direction == .ltr else {
            return false
        }
        let items: [InlineItem] = blockData(id).content.inlineItems
        guard items.allSatisfy({ item in
            if case .text = item { return true }
            return false
        }) else {
            return false
        }
        let children: [LayoutID] = childrenIDs(of: id)
        guard !children.isEmpty, children.allSatisfy({ isLine($0) }) else {
            return false
        }
        return children.allSatisfy({ !lineData($0).content.centered })
    }

    private mutating func updateInlineLineFrames(_ id: LayoutID) {
        let frameX: CGFloat = x(id)
        let frameWidth: CGFloat = width(id)
        let frameZoom: CGFloat = zoom(id)
        for line in childrenIDs(of: id) where isLine(line) {
            setFrame(
                (zoom: frameZoom, x: frameX, y: y(line), width: frameWidth),
                for: line
            )
        }
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
        let data: BlockData = blockData(id)
        let items: [InlineItem] = data.content.inlineItems
        if textRuns[id] == nil {
            textRuns[id] = TextRun(items: items)
        }
        let reusable: [LayoutID] = childrenIDs(of: id).filter({ isLine($0) })
        var placement: InlinePlacement = InlinePlacement(
            parent: id,
            reusableLines: reusable,
            objects: data.content.inlineObjects
        )
        profiler.measure("layout.inline.place.setup", {
            placement.start(in: &self)
        })
        profiler.measure("layout.inline.place.items", {
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
        })
        profiler.measure("layout.inline.place.finish", {
            placement.finish(in: &self)
        })
        if placement.objectsChanged {
            var updated: BlockData = blockData(id)
            updated.content.inlineObjects = placement.objects
            setKind(.block(updated), at: id)
        }
        profiler.measure("layout.inline.place.parentChildren", {
            setInlineChildrenField(placement.lines, of: id)
        })
        profiler.count("layout.lines.total", by: placement.lines.count)
    }

    /// Updates a reused line's owned widths after a font/zoom refresh. The
    /// text nodes keep their identity, but their metrics and line widths must
    /// follow the newly measured items.
    mutating private func refreshReusedLine(
        _ line: LayoutID,
        items: [InlineItem]
    ) {
        let children: [LayoutID] = childrenIDs(of: line)
        var data: LineData = lineData(line)
        guard data.content.inlineWidths.count == children.count else { return }
        var widths: [CGFloat] = data.content.inlineWidths
        for (index, child) in children.enumerated() where isText(child) {
            let text: TextData = textData(child)
            guard let fragment: TextFragment = text.fragment,
                fragment.start >= 0,
                fragment.start + fragment.count <= items.count
            else { continue }
            var width: CGFloat = 0
            for itemIndex in fragment.start..<(fragment.start + fragment.count) {
                guard case .text(let item) = items[itemIndex] else { continue }
                let font: BrowserFont = item.fontOverride ?? item.run.font
                let measured: CGFloat = item.measuredWidth
                    ?? font.measure(item.display ?? item.word)
                width += measured + font.spaceWidth
            }
            widths[index] = width
            var updated: TextData = text
            updated.metrics.width = width
            updated.metrics.measured = true
            setKind(.text(updated), at: child)
            markField(.font, at: child)
            markField(.width, at: child)
        }
        data.content.inlineWidths = widths
        setKind(.line(data), at: line)
    }

    /// Places a changed line plan. Lines whose item range is unchanged keep
    /// their existing children; only shifted or re-broken lines are rebuilt.
    mutating private func placeInlineItems(
        _ id: LayoutID,
        plan: [[Int]],
        oldPlan: [[Int]],
        refreshMetrics: Bool
    ) {
        let data: BlockData = blockData(id)
        let items: [InlineItem] = data.content.inlineItems
        if textRuns[id] == nil {
            textRuns[id] = TextRun(items: items)
        }
        let oldLines: [LayoutID] = childrenIDs(of: id).filter({ isLine($0) })
        var oldLineByStart: [Int: (line: LayoutID, count: Int)] = [:]
        for index in oldPlan.indices where index < oldLines.count {
            guard let start: Int = oldPlan[index].first else { continue }
            oldLineByStart[start] = (oldLines[index], oldPlan[index].count)
        }
        var reusable: [Int: LayoutID] = [:]
        var used: Set<LayoutID> = []
        for index in plan.indices {
            guard let start: Int = plan[index].first,
                let old: (line: LayoutID, count: Int) = oldLineByStart[start],
                old.count == plan[index].count,
                !used.contains(old.line)
            else { continue }
            reusable[index] = old.line
            used.insert(old.line)
        }
        var free: [LayoutID] = oldLines.filter({ !used.contains($0) })
        var placement: InlinePlacement = InlinePlacement(
            parent: id,
            reusableLines: [],
            objects: data.content.inlineObjects
        )
        var lines: [LayoutID] = []
        var previous: LayoutID? = nil
        for (index, range) in plan.enumerated() {
            if let line: LayoutID = reusable[index] {
                if refreshMetrics {
                    refreshReusedLine(line, items: items)
                }
                let previousChanged: Bool = reuseLine(line, previous: previous)
                setLineChildrenField(
                    childrenIDs(of: line),
                    of: line,
                    previousChanged: previousChanged
                )
                lines.append(line)
                previous = line
                profiler.count("layout.inline.place.reusedLines")
                continue
            }
            let line: LayoutID
            if let freeLine: LayoutID = free.popLast() {
                line = freeLine
            } else {
                line = makeLine(dom: node(id).dom, parent: id, previous: previous)
            }
            placement.start(at: line, previous: previous, in: &self)
            for itemIndex in range {
                guard case .text(let text) = items[itemIndex] else { continue }
                let font: BrowserFont = text.fontOverride ?? text.run.font
                let measured: CGFloat = text.measuredWidth ?? font.measure(text.display ?? text.word)
                let w: CGFloat = measured + font.spaceWidth
                placement.appendText(text, width: w, index: itemIndex, in: &self)
            }
            placement.finish(in: &self)
            lines.append(line)
            previous = line
            profiler.count("layout.inline.place.rebuiltLines")
        }
        if placement.objectsChanged {
            var updated: BlockData = blockData(id)
            updated.content.inlineObjects = placement.objects
            setKind(.block(updated), at: id)
        }
        setInlineChildrenField(lines, of: id)
        profiler.count("layout.lines.total", by: lines.count)
    }

    private static let inlineFontProperties: Set<StyleProperty> = [
        .fontSize, .fontFamily, .fontWeight, .fontStyle,
    ]

    private func canRefreshFontsOnly(_ id: LayoutID) -> Bool {
        guard !isDirty(.children, at: id),
            blockData(id).changes.childChanges.isEmpty
        else { return false }
        if inputs.styleChanges(domID(of: id)).contains(where: {
            LayoutInputTable.structuralStyleProperties.contains($0)
        }) {
            return false
        }
        for leaf in inlineLeaves(id) {
            let owner: LayoutDOMView = leaf.inheritedStyleOwner
            let changes: Set<StyleProperty> = inputs.styleChanges(owner.id)
            if changes.contains(where: {
                LayoutInputTable.structuralStyleProperties.contains($0)
            }) {
                return false
            }
            if leaf.text != nil, isInsideAbbr(leaf.ref) {
                return false
            }
        }

        var fontChanged: Bool = isDirty(.zoom, at: id)
        for leaf in inlineLeaves(id) {
            let owner: LayoutDOMView = leaf.inheritedStyleOwner
            let changes: Set<StyleProperty> = inputs.styleChanges(owner.id)
            if !changes.isDisjoint(with: Self.inlineFontProperties) {
                fontChanged = true
            }
        }
        return fontChanged
    }

    private func canScaleMeasuredWidths(_ id: LayoutID) -> Bool {
        let disallowed: Set<StyleProperty> = [.fontFamily, .fontWeight, .fontStyle]
        for leaf in inlineLeaves(id) {
            let owner: LayoutDOMView = leaf.inheritedStyleOwner
            for change in inputs.styleChanges(owner.id) where disallowed.contains(change) {
                return false
            }
        }
        return true
    }

    /// Returns true when the existing inline item ranges are still valid and
    /// the old line plan may be reused for placement.
    @discardableResult
    mutating private func refreshInlineItems(_ id: LayoutID, preservingObjects: Bool) -> Bool {
        var data: BlockData = blockData(id)
        if preservingObjects, !data.content.inlineItems.isEmpty {
            let zoom: CGFloat = zoom(id)
            let scaleWidths: Bool = canScaleMeasuredWidths(id)
            var items: [InlineItem] = data.content.inlineItems
            var fonts: [NodeID: BrowserFont] = [:]
            var scales: [NodeID: CGFloat] = [:]
            for index in items.indices {
                guard case .text(let item) = items[index] else { continue }
                let node: NodeID = item.run.node.id
                let font: BrowserFont
                if let cached: BrowserFont = fonts[node] {
                    font = cached
                } else {
                    font = fontFor(node, zoom: zoom)
                    fonts[node] = font
                }
                let scale: CGFloat?
                if scaleWidths {
                    if let cached: CGFloat = scales[node] {
                        scale = cached
                    } else {
                        let next: CGFloat = font.size / item.run.font.size
                        scales[node] = next
                        scale = next
                    }
                } else {
                    scale = nil
                }
                items[index] = .text(item.withFont(font, measuredWidthScale: scale))
            }
            data.content.inlineItems = items
            if textRuns[id] == nil {
                textRuns[id] = TextRun(items: items)
            }
            profiler.count("layout.inline.items.reused", by: items.count)
        } else {
            let leaves: [LayoutDOMView] = inlineLeaves(id)
            var items: [InlineItem] = []
            for leaf in leaves {
                items.append(contentsOf: makeItems(id, for: leaf))
            }
            data.content.inlineItems = items
            textRuns[id] = TextRun(items: items)
            if !preservingObjects {
                data.content.inlineObjects.removeAll(keepingCapacity: true)
            }
            profiler.count("layout.inline.items.rebuilt", by: items.count)
        }
        if !preservingObjects || data.content.inlineItems.isEmpty {
            data.content.inlineLinePlan = nil
        }
        let reusablePlan: Bool = preservingObjects && !data.content.inlineItems.isEmpty
        setKind(.block(data), at: id)
        let revision: UInt64 = node(id).state.fields.inlineText.inlineContent + 1
        setInlineContent(revision, for: id)
        return reusablePlan
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
        placement.flushText(in: &self)
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
        let brokeEarly: Bool = {
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
                        placement.flushText(in: &self)
                        appendToLine(id, clone(item, word: chunk + "-"), index: nil, into: &placement)
                        placement.endLine(in: &self)
                        placeText(
                            id,
                            clone(item, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}")),
                            index: nil,
                            into: &placement
                        )
                        return true
                    }
                }
                placement.endLine(in: &self)
            }
            return false
        }()
        if brokeEarly { return }

        var measuredItem: InlineTextItem = item
        if measuredItem.measuredWidth == nil {
            measuredItem.measuredWidth = measured
        }
        placement.appendText(measuredItem, width: w, index: index ?? 0, in: &self)
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
            let object: LayoutID = placement.object(at: index),
            let cached: LayoutID = cachedText(object, node: item.run.node, word: item.word)
        {
            text = cached
            profiler.count("layout.inline.text.cached")
            setFontAndPrevious(
                font,
                previous: previous,
                measuredWidth: item.measuredWidth,
                for: text
            )
        } else {
            profiler.count("layout.inline.text.new")
            text = makeText(
                TextData(
                    payload: TextPayload(
                        word: item.word,
                        display: item.display,
                        fontOverride: item.fontOverride
                    ),
                    fragment: nil,
                    metrics: TextMetrics(
                        width: item.measuredWidth ?? 0,
                        whiteSpace: item.run.whiteSpace,
                        measured: item.measuredWidth != nil
                    )
                ),
                dom: item.run.node.id,
                parent: lineID,
                previous: previous
            )
            setFontAndPrevious(
                font,
                previous: previous,
                measuredWidth: item.measuredWidth,
                for: text
            )
            if let index {
                placement.setObject(text, at: index)
            }
        }
        placement.append(text, width: item.measuredWidth ?? font.measure(item.display ?? item.word) + font.spaceWidth)
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
        if let object: LayoutID = placement.object(at: index),
            let cached: LayoutID = cachedEmbed(object, .input, node: node)
        {
            input = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            input = makeEmbed(dom: node.ref.id, data: .input, parent: lineID, previous: previous)
            placement.setObject(input, at: index)
        }
        placement.append(input, width: w)

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
        if let object: LayoutID = placement.object(at: index),
            let cached: LayoutID = cachedEmbed(object, .button, node: node)
        {
            button = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            button = makeEmbed(
                dom: node.ref.id,
                data: .button(ButtonData(cursorX: 0)),
                parent: lineID,
                previous: previous
            )
            placement.setObject(button, at: index)
        }
        placement.append(button, width: w)
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
        if let object: LayoutID = placement.object(at: index),
            let cached: LayoutID = cachedEmbed(object, .image, node: node)
        {
            image = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            image = makeEmbed(
                dom: node.ref.id,
                data: .image(ImageData(imageHeight: 0)),
                parent: lineID,
                previous: previous
            )
            placement.setObject(image, at: index)
        }
        placement.append(image, width: w)

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
        if let object: LayoutID = placement.object(at: index),
            let cached: LayoutID = cachedEmbed(object, .iframe, node: node)
        {
            iframe = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            iframe = makeEmbed(
                dom: node.ref.id,
                data: .iframe,
                parent: lineID,
                previous: previous
            )
            placement.setObject(iframe, at: index)
        }
        placement.append(iframe, width: w)

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
        if let object: LayoutID = placement.object(at: index),
            let cached: LayoutID = cachedEmbed(object, .canvas, node: node)
        {
            canvas = cached
            attachEmbed(cached, to: lineID, previous: previous)
        } else {
            canvas = makeEmbed(
                dom: node.ref.id,
                data: .canvas,
                parent: lineID,
                previous: previous
            )
            placement.setObject(canvas, at: index)
        }
        placement.append(canvas, width: w)

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
        node: LayoutDOMView,
        word: String
    ) -> LayoutID? {
        guard contains(id) else { return nil }
        guard isText(id),
            domID(of: id) == node.id,
            textData(id).payload.word == word
        else { return nil }
        return id
    }

    private func cachedEmbed(
        _ id: LayoutID,
        _ kind: EmbedMatch,
        node: LayoutElementView
    ) -> LayoutID? {
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
    var objects: [Int: LayoutID]
    var objectsChanged: Bool = false
}

private struct PendingTextStyle {
    let node: NodeID
    let font: BrowserFont
}

private struct PendingText {
    let style: PendingTextStyle
    let start: Int
    var count: Int
    var width: CGFloat
}

private struct InlineLineContent {
    var children: [LayoutID] = []
    var pending: PendingText? = nil
    var reuseText: [LayoutID] = []
    var widths: [CGFloat] = []
}

private struct InlinePlacementState {
    var lines: [LayoutID] = []
    var currentLine: LayoutID? = nil
    var content: InlineLineContent = InlineLineContent()
    var cursorX: CGFloat = 0
}

private struct LinePool {
    private let lines: [LayoutID]
    private var next: Int = 0

    init(_ lines: [LayoutID]) {
        self.lines = lines
    }

    mutating func take() -> LayoutID? {
        guard next < lines.count else { return nil }
        let line: LayoutID = lines[next]
        next += 1
        return line
    }
}

struct InlinePlacement {
    private var context: InlinePlacementContext
    private var state: InlinePlacementState = InlinePlacementState()
    private var pool: LinePool
    private var previousChanged: Bool = false

    init(parent: LayoutID, reusableLines: [LayoutID], objects: [Int: LayoutID]) {
        self.context = InlinePlacementContext(parent: parent, objects: objects)
        self.pool = LinePool(reusableLines)
    }

    var lines: [LayoutID] { state.lines }
    var currentLine: LayoutID? { state.currentLine }
    var children: [LayoutID] { state.content.children }
    var objects: [Int: LayoutID] { context.objects }
    var objectsChanged: Bool { context.objectsChanged }

    func object(at index: Int) -> LayoutID? {
        return context.objects[index]
    }

    mutating func setObject(_ id: LayoutID, at index: Int) {
        context.objects[index] = id
        context.objectsChanged = true
    }
    var cursorX: CGFloat {
        get { state.cursorX }
        set { state.cursorX = newValue }
    }

    mutating func start(in tree: inout LayoutTree) {
        let previous: LayoutID? = state.lines.last
        if let line: LayoutID = pool.take() {
            let reuseText: [LayoutID] = tree.childrenIDs(of: line).filter({ tree.isText($0) })
            previousChanged = tree.resetLine(line, previous: previous)
            state.currentLine = line
            state.content = InlineLineContent(reuseText: reuseText)
        } else {
            state.currentLine = tree.makeLine(
                dom: tree.node(context.parent).dom,
                parent: context.parent,
                previous: previous
            )
            previousChanged = true
            state.content = InlineLineContent()
        }
        state.cursorX = 0
    }

    @discardableResult
    mutating func start(
        at line: LayoutID,
        previous: LayoutID?,
        in tree: inout LayoutTree
    ) -> Bool {
        let reuseText: [LayoutID] = tree.childrenIDs(of: line).filter({ tree.isText($0) })
        previousChanged = tree.resetLine(line, previous: previous)
        state.currentLine = line
        state.content = InlineLineContent(reuseText: reuseText)
        state.cursorX = 0
        return previousChanged
    }

    mutating func endLine(in tree: inout LayoutTree) {
        guard let line: LayoutID = state.currentLine else { return }
        flushText(in: &tree)
        commitLine(line, in: &tree)
        state.lines.append(line)
        start(in: &tree)
    }

    mutating func finish(in tree: inout LayoutTree) {
        guard let line: LayoutID = state.currentLine else { return }
        flushText(in: &tree)
        commitLine(line, in: &tree)
        state.lines.append(line)
        state.currentLine = nil
        state.content = InlineLineContent()
    }

    mutating func appendText(_ item: InlineTextItem, width: CGFloat, index: Int, in tree: inout LayoutTree) {
        let font: BrowserFont = item.fontOverride ?? item.run.font
        let style: PendingTextStyle = PendingTextStyle(node: item.run.node.id, font: font)
        if var pending: PendingText = state.content.pending,
            pending.style.node == style.node,
            CFEqual(pending.style.font.ctFont, style.font.ctFont),
            index == pending.start + pending.count,
            !item.hasSoftHypen
        {
            pending.count += 1
            pending.width += width
            state.content.pending = pending
            return
        }
        flushText(in: &tree)
        state.content.pending = PendingText(
            style: style,
            start: index,
            count: 1,
            width: width
        )
    }

    mutating func flushText(in tree: inout LayoutTree) {
        guard let pending: PendingText = state.content.pending,
            let line: LayoutID = state.currentLine
        else { return }
        let previous: LayoutID? = state.content.children.last
        let fragment: TextFragment = TextFragment(
            block: context.parent,
            start: pending.start,
            count: pending.count
        )
        let text: LayoutID
        if state.content.reuseText.isEmpty {
            text = tree.makeText(
                TextData(
                    payload: TextPayload(word: "", display: nil, fontOverride: nil),
                    fragment: fragment,
                    metrics: TextMetrics(width: pending.width, whiteSpace: .normal, measured: true)
                ),
                dom: pending.style.node,
                parent: line,
                previous: previous
            )
        } else {
            text = state.content.reuseText.removeFirst()
            var data: TextData = tree.textData(text)
            data.fragment = fragment
            data.payload.word = ""
            data.payload.display = nil
            data.metrics.width = pending.width
            data.metrics.measured = true
            tree.setKind(.text(data), at: text)
        }
        tree.setFontAndPrevious(
            pending.style.font,
            previous: previous,
            measuredWidth: nil,
            for: text
        )
        state.content.children.append(text)
        state.content.widths.append(pending.width)
        state.content.pending = nil
    }

    mutating func append(_ child: LayoutID, width: CGFloat) {
        state.content.children.append(child)
        state.content.widths.append(width)
    }

    private mutating func commitLine(_ line: LayoutID, in tree: inout LayoutTree) {
        var data: LineData = tree.lineData(line)
        data.content.inlineWidths = state.content.widths
        tree.setKind(.line(data), at: line)
        profiler.measure("layout.inline.place.lineChildren", {
            tree.setLineChildrenField(
                state.content.children,
                of: line,
                previousChanged: previousChanged
            )
        })
    }
}

