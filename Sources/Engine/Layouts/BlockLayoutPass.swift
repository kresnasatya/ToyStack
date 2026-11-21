import CoreGraphics

// MARK: - BlockLayoutPass

extension LayoutTree {
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
        self[block: id].content.extraNodes = extraNodes
        setPreviousClean(previous, of: id)
        for field in [
            LayoutField.zoom, .x, .y, .width, .inlineContent, .children,
        ] {
            markUsed(field, at: id)
        }
        markAncestorsDirty(from: id)
    }

    func blockExtraNodes(_ id: LayoutID) -> [LayoutDOMView] {
        return self[block: id].content.extraNodes.map({ domView($0) })
    }

    /// Cheaper than `blockExtraNodes(_:).isEmpty`, which builds the
    /// views.
    func hasExtraNodes(_ id: LayoutID) -> Bool {
        return !self[block: id].content.extraNodes.isEmpty
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
            for child in self.inputs.allChildren(domID(of: id)) {
                inputs.append(.style(child, .display))
                inputs.append(.style(child, .position))
            }
        }
        var leaves: [LayoutDOMView] = []
        var hidden: [NodeID] = []
        collectInline(id, leaves: &leaves, hidden: &hidden)
        var boxed: Set<NodeID> = []
        for leaf in leaves {
            let owner: LayoutDOMView = leaf.inheritedStyleOwner
            inputs.append(.style(owner.id, .whiteSpace))
            inputs.append(contentsOf: fontInputs(for: leaf.id, in: self.inputs))
            if let el = leaf.element {
                inputs.append(.style(el.ref.id, .aspectRatio))
                inputs.append(.style(el.ref.id, .maxWidth))
                inputs.append(.style(el.ref.id, .boxSizing))
                inputs.append(contentsOf: LayoutInputTable.boxEdgeKeys(el.ref.id))
            }
            var ancestor: LayoutDOMView? = leaf.parent
            while let node = ancestor, node.style.computed.layout.display == .inline {
                if boxed.insert(node.id).inserted {
                    inputs.append(.style(node.id, .display))
                    inputs.append(.style(node.id, .direction))
                    inputs.append(contentsOf: LayoutInputTable.boxEdgeKeys(node.id))
                }
                ancestor = node.parent
            }
        }
        for node in hidden {
            inputs.append(.style(node, .display))
        }
        return inputs
    }

    private func inlineLeaves(_ id: LayoutID) -> [LayoutDOMView] {
        var leaves: [LayoutDOMView] = []
        var hidden: [NodeID] = []
        collectInline(id, leaves: &leaves, hidden: &hidden)
        return leaves
    }

    /// `hidden` gets the `display: none` elements the walk skips. They leave no
    /// leaf behind, yet showing one must still refresh this block's inline content.
    private func collectInline(
        _ id: LayoutID,
        leaves: inout [LayoutDOMView],
        hidden: inout [NodeID]
    ) {
        let extraNodes: [LayoutDOMView] = blockExtraNodes(id)
        if !extraNodes.isEmpty {
            for node in extraNodes { collectLeaves(node, leaves: &leaves, hidden: &hidden) }
            return
        }
        let hasBlockChild: Bool = domView(id).children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if !hasBlockChild {
            collectLeaves(domView(id), leaves: &leaves, hidden: &hidden)
            return
        }
        for child in domView(id).children where child.style.computed.layout.display != .block {
            collectLeaves(child, leaves: &leaves, hidden: &hidden)
        }
    }

    func blockChildrenInputs(_ id: LayoutID) -> [FieldKey] {
        guard layoutMode(id) == .block else { return [] }
        var inputs: [FieldKey] = []
        for child in self.inputs.allChildren(domID(of: id)) {
            inputs.append(.style(child, .display))
            inputs.append(.style(child, .position))
            inputs.append(.style(child, .float))
        }
        return inputs
    }

    // MARK: - Line plan

    mutating private func inlineTextLinePlan(_ id: LayoutID) -> InlineLinePlan? {
        let availableWidth: CGFloat = width(id)
        if let stored: InlineLinePlan = self[block: id].content.inlineLinePlan,
            stored.fits?.contains(availableWidth) == true
        {
            return stored
        }
        profiler.count("layout.inline.plan.computed")
        let items: [InlineItem] = self[block: id].content.inlineItems
        var plan: [[Int]] = []
        var current: [Int] = []
        var cursorX: CGFloat = 0
        var updated: [InlineItem] = items
        var measuredNewWord: Bool = false
        var widestKept: CGFloat = 0
        var narrowestBreak: CGFloat = .infinity

        for index in updated.indices {
            switch updated[index] {
            case .lineBreak:
                plan.append(current)
                current = []
                cursorX = 0
            case .embed, .boxEdge:
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
                    measuredNewWord = true
                }
                let width: CGFloat = wordWidth + font.spaceWidth
                if text.run.whiteSpace.wraps {
                    let end: CGFloat = cursorX + width
                    if end > availableWidth {
                        narrowestBreak = min(narrowestBreak, end)
                        plan.append(current)
                        current = []
                        cursorX = 0
                    } else {
                        widestKept = max(widestKept, end)
                    }
                }
                current.append(index)
                cursorX += width
            }
        }

        if measuredNewWord {
            self[block: id].content.inlineItems = updated
        }
        plan.append(current)
        return InlineLinePlan(lines: plan, fits: widestKept..<narrowestBreak)
    }

    mutating private func setHeightInputs(_ id: LayoutID) {
        let children: [LayoutID] = childrenIDs(of: id)
        let declared: [LayoutID] = self[block: id].changes.declaredHeightChildren
        let unchanged: Bool = children == declared
        if unchanged { return }
        self[block: id].changes.declaredHeightChildren = children
        markUsed(.height, at: id)
    }

    func blockHeightInputs(_ id: LayoutID) -> [FieldKey] {
        var inputs: [FieldKey] = [
            .layout(id, .children),
            .layout(id, .zoom),
            .style(domID(of: id), .height),
            .style(domID(of: id), .boxSizing),
            .style(domID(of: id), .paddingTop),
            .style(domID(of: id), .paddingBottom),
            .style(domID(of: id), .borderWidth),
            .style(domID(of: id), .borderStyle),
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
                inputs.append(.style(domID(of: child), .borderWidth))
                inputs.append(.style(domID(of: child), .borderStyle))
                inputs.append(.style(domID(of: child), .float))
                inputs.append(.style(domID(of: child), .clear))
                if blockFloating(child).clear != .none {
                    inputs.append(.layout(child, .y))
                    inputs.append(.layout(id, .y))
                }
            }
        }
        return inputs
    }

    mutating func blockMarkChildrenDirty(_ id: LayoutID) {
        self[block: id].changes.childChanges.removeAll()
        markField(.inlineContent, at: id)
        markField(.children, at: id)
    }

    mutating func blockNoteAppendedChildren(_ id: LayoutID, _ nodes: [NodeID]) {
        self[block: id].changes.childChanges.append(.append(nodes))
        markAncestorsDirty(from: id)
    }

    mutating func blockNoteInsertedChildren(_ id: LayoutID, _ nodes: [NodeID], before reference: NodeID) {
        self[block: id].changes.childChanges.append(.insert(nodes, before: reference))
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
        let state: FieldState = self[node: id].state.fields.state
        if state.isDirty(.zoom) || state.isDirty(.x) || state.isDirty(.y)
            || state.isDirty(.width) || state.isDirty(.height)
        {
            return true
        }
        return state.isDirty(.inlineContent)
            || state.isDirty(.children)
            || !self[block: id].changes.childChanges.isEmpty
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
        let visitSpan: ProfileSpan = profiler.begin("layout.visit")
        do {
            profiler.count("layout.rebuilt")
            if geometryDirty {
                let geometrySpan: ProfileSpan = profiler.begin("layout.visit.geometry")
                placeBlockFrame(id, style: style)
                profiler.end(geometrySpan)
            }
            let frameMoved: Bool = geometryDirty
                && (!frameWasClean || x(id) != oldFrameX || y(id) != oldFrameY)
            let widthChanged: Bool = geometryDirty && widthWasDirty
            if frameMoved {
                for child in childrenIDs(of: id) where isLine(child) {
                    markField(.y, at: child)
                }
            }

            let modeSpan: ProfileSpan = profiler.begin("layout.mode")
            let mode: LayoutMode = layoutMode(id)
            profiler.end(modeSpan)
            if mode == .block {
                profiler.count("layout.mode.block")
                if isDirty(.children, at: id) {
                    setChildrenField(rebuildBlockChildren(id), of: id)
                } else if !self[block: id].changes.childChanges.isEmpty {
                    let changes: [BlockChildChange] = self[block: id].changes.childChanges
                    self[block: id].changes.childChanges.removeAll()
                    if let changed: [LayoutID] = applyBlockChanges(id, changes) {
                        countChildChanges(changes)
                        setChildrenField(changed, of: id)
                    } else {
                        setChildrenField(rebuildBlockChildren(id), of: id)
                    }
                }

                if isDirty(.inlineContent, at: id) {
                    let revision: UInt64 = storedInlineContent(id) + 1
                    setInlineContentClean(revision, for: id)
                    self[block: id].content.inlineObjects.removeAll(keepingCapacity: true)
                    self[block: id].content.inlineLinePlan = nil
                }
            } else {
                profiler.count("layout.mode.inline")
                let hasChildChanges: Bool = !self[block: id].changes.childChanges.isEmpty
                let inlineContentChanged: Bool = isDirty(.inlineContent, at: id) || hasChildChanges
                if hasChildChanges {
                    self[block: id].changes.childChanges.removeAll()
                }
                _ = zoom(id)

                var preservedItems: Bool = false
                if inlineContentChanged {
                    let preserveObjects: Bool = canRefreshFontsOnly(id)
                    let refreshSpan: ProfileSpan = profiler.begin("layout.inline.refresh")
                    preservedItems = refreshInlineItems(id, preservingObjects: preserveObjects)
                    profiler.end(refreshSpan)
                }
                let floats: FloatExclusions = floatExclusions(for: id)
                let floatsChanged: Bool = noteWrapped(id, floats)
                let oldPlan: InlineLinePlan? = self[block: id].content.inlineLinePlan
                let planSpan: ProfileSpan = profiler.begin("layout.inline.plan")
                // The cached plan assumes one width for every line.
                let plan: InlineLinePlan? = floats.isEmpty ? inlineTextLinePlan(id) : nil
                profiler.end(planSpan)
                let shouldPlace: Bool = inlineContentChanged
                    || floatsChanged
                    || plan == nil
                    || plan?.lines != oldPlan?.lines
                let canReusePlan: Bool = !inlineContentChanged || preservedItems
                if !shouldPlace, widthChanged, !frameMoved,
                    !isDirty(.height, at: id),
                    canSkipInlineChildren(id)
                {
                    updateInlineLineFrames(id)
                    skipInlineChildren = true
                }
                if shouldPlace {
                    let placeSpan: ProfileSpan = profiler.begin("layout.inline.place")
                    if canReusePlan, let plan, let oldPlan {
                        placeInlineItems(
                            id,
                            plan: plan.lines,
                            oldPlan: oldPlan.lines,
                            refreshMetrics: preservedItems
                        )
                    } else {
                        placeInlineItems(id, floats: floats)
                    }
                    profiler.end(placeSpan)
                } else {
                    setChildrenField(childrenIDs(of: id), of: id)
                }
                if self[block: id].content.inlineLinePlan != plan {
                    self[block: id].content.inlineLinePlan = plan
                }
            }
        }
        profiler.end(visitSpan)

        var measuredHeight: CGFloat? = nil
        if !skipInlineChildren {
            let childrenSpan: ProfileSpan = profiler.begin("layout.visit.children")
            for child in childrenIDs(of: id) { layout(child) }
            profiler.end(childrenSpan)

            setHeightInputs(id)
            let heightChildren: [LayoutID] = childrenIDs(of: id)
            let heightSpan: ProfileSpan = profiler.begin("layout.height")
            measuredHeight = flowHeight(of: heightChildren, in: id)
            profiler.end(heightSpan)
        } else {
            profiler.count("layout.inline.children.skipped")
        }

        let storedScroll: BlockScroll = self[block: id].scroll
        var scroll: BlockScroll = storedScroll
        if let sumHeight = measuredHeight {
            scroll.contentHeight = sumHeight
            let size: BoxStyle.Size = domView(id).style.computed.box.size
            if let h: CGFloat = size.height {
                let styleHeightZoom: CGFloat = zoom(id)
                let usedHeight: CGFloat = size.boxSizing.contentSize(
                    specified: h * styleHeightZoom,
                    paddingAndBorder: paddingVertical(id) + borderWidths(id).vertical
                )
                setField(.height, usedHeight, for: id)
            } else {
                setField(.height, sumHeight, for: id)
            }
        }

        if let el = domView(id).element, el.attributes["id"] == "toc" {
            setField(.height, height(id) + VSTEP, for: id)
        }

        if scroll.contentHeight != storedScroll.contentHeight {
            self[block: id].scroll = scroll
        }
        recordFloatBox(id)
    }

    private func countWidthChange(from old: GeometryFields, widthWasUsed: Bool, at id: LayoutID) {
        let new: GeometryFields = self[node: id].state.fields.geometry
        if !widthWasUsed || old.size.width != new.size.width {
            profiler.count("layout.width.changed")
        } else if old.origin.x != new.origin.x {
            profiler.count("layout.width.same.xMoved")
        } else if old.origin.y != new.origin.y {
            profiler.count("layout.width.same.yMoved")
        } else {
            profiler.count("layout.width.same.unmoved")
        }
    }

    mutating private func placeBlockFrame(_ id: LayoutID, style: BlockStyle) {
        let zoomValue: CGFloat = resolvedZoom(id)
        let isAbsolute: Bool = style.position == .absolute
        let parent: LayoutID = parentID(of: id)!

        let parentX: CGFloat = x(parent)
        let ownBorder: EdgeInsets = borderValues(id).scaled(by: zoomValue)
        let padLeft: CGFloat = !hasExtraNodes(id)
            ? style.box.padding.left * zoomValue
            : 0
        let marginLeft: CGFloat = !hasExtraNodes(id) ? style.box.margin.left * zoomValue : 0
        let marginRight: CGFloat = !hasExtraNodes(id) ? style.box.margin.right * zoomValue : 0
        var frameX: CGFloat
        if isAbsolute, let l = style.flags.left {
            frameX = l * zoomValue + marginLeft + padLeft + ownBorder.left
        } else {
            frameX = parentX + marginLeft + padLeft + ownBorder.left
        }

        let parentWidth: CGFloat = width(parent)
        let padHorizontal: CGFloat = !hasExtraNodes(id)
            ? (style.box.padding.left + style.box.padding.right) * zoomValue
            : 0
        let floating: LayoutStyle.Floating = isAbsolute ? .none : blockFloating(id)
        var frameWidth: CGFloat
        if let w = style.box.size.width {
            frameWidth = style.box.size.boxSizing.contentSize(
                specified: w * zoomValue,
                paddingAndBorder: padHorizontal + ownBorder.horizontal
            )
        } else {
            frameWidth = max(0, parentWidth - marginLeft - marginRight - padHorizontal - ownBorder.horizontal)
            if floating.side != .none {
                // CSS 2.1 §10.3.5: an auto-width float shrinks to fit its content.
                let preferred: IntrinsicWidths = intrinsicWidths(
                    of: domView(id),
                    zoom: zoomValue,
                    available: frameWidth
                )
                frameWidth = min(max(preferred.minContent, frameWidth), preferred.maxContent)
            }
        }

        let element = domView(id).element
        if element?.tag == "li" {
            frameX += liIndent
            frameWidth -= liIndent
        }

        var frameY: CGFloat
        var besideFloats: Bool = false
        if isAbsolute, let t = style.flags.top {
            let padTop: CGFloat = !hasExtraNodes(id)
                ? style.box.padding.left * zoomValue
                : 0
            frameY = t * zoomValue + padTop + ownBorder.top
        } else {
            let ownTop: CGFloat = style.box.margin.top * zoomValue
            let padTop: CGFloat = style.box.padding.top * zoomValue
            if let previous: LayoutID = blockPrevious(id) {
                let prevY: CGFloat = y(previous)
                let prevHeight: CGFloat = height(previous)
                let prevPadBottom: CGFloat = isBlock(previous)
                    ? padding(previous, .paddingBottom)
                    : 0
                let prevBorderBottom: CGFloat = isBlock(previous)
                    ? borderWidths(previous).bottom
                    : 0
                let prevMarginBottom: CGFloat = isBlock(previous)
                    ? blockStyle(previous).box.margin.bottom
                    : 0
                frameY = prevY + prevHeight + prevPadBottom + prevBorderBottom
                    + prevMarginBottom * zoomValue + ownTop + ownBorder.top + padTop
            } else {
                frameY = y(parent) + ownTop + ownBorder.top + padTop
            }
            if floating.side != .none {
                let flowTop: CGFloat = frameY - ownTop - ownBorder.top - padTop
                let marginBoxWidth: CGFloat = marginLeft + ownBorder.horizontal + padHorizontal
                    + frameWidth + marginRight
                let origin: CGPoint = floatPlacer(for: id, top: flowTop).origin(
                    side: floating.side,
                    width: marginBoxWidth,
                    top: flowTop,
                    clear: floating.clear
                )
                frameX = origin.x + marginLeft + ownBorder.left + padLeft
                frameY = origin.y + ownTop + ownBorder.top + padTop
            } else if floating.clear != .none,
                let bottom: CGFloat = floatBottom(before: id, clearing: floating.clear)
            {
                // CSS 2.1 §9.5.2: clearance puts the top border edge below the
                // bottom outer edge of the cleared floats.
                frameY = max(frameY, bottom + ownBorder.top + padTop)
            }
            if floating.side == .none, !isAbsolute, !hasExtraNodes(id), establishesFormattingContext(id) {
                // CSS 2.1 §9.5: a block that starts its own formatting context
                // keeps its margin box off earlier floats: beside them when it
                // fits, below them when it does not.
                let marginTop: CGFloat = frameY - ownTop - ownBorder.top - padTop
                let placer: FloatPlacer = floatPlacer(for: id, top: marginTop)
                if !placer.earlier.isEmpty {
                    besideFloats = true
                    let outside: CGFloat = marginLeft + ownBorder.horizontal + padHorizontal + marginRight
                    let isAutoWidth: Bool = style.box.size.width == nil
                    let needed: CGFloat = isAutoWidth
                        ? intrinsicWidths(of: domView(id), zoom: zoomValue, available: frameWidth).minContent
                        : frameWidth
                    let room: FloatRoom = placer.room(top: marginTop, width: needed + outside)
                    frameY += room.top - marginTop
                    frameX = room.left + marginLeft + ownBorder.left + padLeft
                    if isAutoWidth {
                        frameWidth = max(0, room.right - room.left - outside)
                    }
                }
            }
        }
        notePositioned(id, floating.side != .none || floating.clear != .none || besideFloats)

        if element?.attributes["id"] == "toc" {
            frameY += VSTEP
        }

        let oldGeometry: GeometryFields = self[node: id].state.fields.geometry
        let widthWasUsed: Bool = isUsed(.width, at: id)
        setFrame(
            (zoom: zoomValue, x: frameX, y: frameY, width: frameWidth),
            for: id
        )
        countWidthChange(from: oldGeometry, widthWasUsed: widthWasUsed, at: id)
    }

    mutating private func flowHeight(of children: [LayoutID], in parent: LayoutID) -> CGFloat {
        var total: CGFloat = 0
        for childID in children {
            let position: LayoutStyle.Position = domView(childID).style.computed.layout.position.kind
            if position == .absolute { return total }
            var h: CGFloat = height(childID)
            if isBlock(childID) {
                let floating: LayoutStyle.Floating = blockFloating(childID)
                if floating.side != .none { continue }
                let childStyle: BlockStyle = blockStyle(childID)
                let childZoom: CGFloat = zoom(childID)
                if isPositionedByFloats(childID) {
                    // Clearance or the floats beside it moved this block down;
                    // the gap belongs to the parent.
                    let marginTop: CGFloat = y(childID) - childStyle.box.padding.top * childZoom
                        - borderWidths(childID).top - childStyle.box.margin.top * childZoom
                    total = max(total, marginTop - y(parent))
                }
                h += (childStyle.box.padding.top + childStyle.box.padding.bottom) * childZoom
                h += borderWidths(childID).vertical
                h += (childStyle.box.margin.top + childStyle.box.margin.bottom) * childZoom
            } else if isLine(childID) {
                h += self[line: childID].placement.floatInsets.gap
            }
            total += h
        }
        return total
    }

    private enum LayoutMode {
        case block
        case inline
    }

    private func layoutMode(_ id: LayoutID) -> LayoutMode {
        if hasExtraNodes(id) { return .inline }
        let node: NodeID = domID(of: id)
        let inputs: LayoutInputs = inputs
        if inputs.text(node) != nil { return .inline }
        if inputs.hasBlockChild(node) { return .block }
        guard let tag: String = inputs.tag(node) else { return .inline }
        let replaced: Bool = tag == "input" || tag == "img" || tag == "iframe" || tag == "canvas"
        return inputs.children(node).isEmpty && !replaced ? .block : .inline
    }

    /// A width-only change that keeps the break plan leaves line contents and
    /// heights intact. Left-to-right text with no embeds only needs new line
    /// widths, so its line children do not have to be visited again.
    private func canSkipInlineChildren(_ id: LayoutID) -> Bool {
        guard inputs.style(domID(of: id)).text.direction == .ltr else {
            return false
        }
        let items: [InlineItem] = self[block: id].content.inlineItems
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
        return children.allSatisfy({ !self[line: $0].content.centered })
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
        self[block: id].changes.childChanges.removeAll()
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
        guard !hasExtraNodes(id),
            current.allSatisfy({ isBlock($0) })
        else {
            return nil
        }
        if let lastID: LayoutID = current.last {
            if !hasExtraNodes(lastID), domView(lastID).element?.tag == "h6" {
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
        guard !hasExtraNodes(id),
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
            if hasExtraNodes(previous) {
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
            let isFlow: Bool = hasExtraNodes(id) || !isOutOfFlow(domView(id))
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
        return nodes.first(where: { $0.style.computed.layout.display != .none })
    }

    private func lastFlowChild(_ id: LayoutID, in children: [LayoutID]) -> LayoutID? {
        for id in children.reversed() {
            if isBlock(id), hasExtraNodes(id) {
                return id
            }
            if !isOutOfFlow(domView(id)) {
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
            if child.style.computed.layout.display == .none {
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
                        if !isOutOfFlow(child) {
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
        guard !hasExtraNodes(id) else { return 0 }
        return max(0, paddingValue(id, side) * zoom(id))
    }

    private func paintedPadding(_ id: LayoutID, _ side: StyleProperty) -> CGFloat {
        guard !hasExtraNodes(id) else { return 0 }
        return max(0, paddingValue(id, side) * zoom(id))
    }

    func paddingVertical(_ id: LayoutID) -> CGFloat {
        return padding(id, .paddingTop) + padding(id, .paddingBottom)
    }

    func boxHeight(_ id: LayoutID) -> CGFloat {
        return height(id) + paddingVertical(id) + borderWidths(id).vertical
    }

    // MARK: - Border

    private func borderValues(_ id: LayoutID) -> EdgeInsets {
        guard !hasExtraNodes(id) else { return .zero }
        return domView(id).style.computed.box.decoration.border.usedWidths
    }

    func blockBorderWidths(_ id: LayoutID) -> EdgeInsets {
        return borderValues(id).scaled(by: zoom(id))
    }

    // MARK: - Inline items

    mutating private func placeInlineItems(_ id: LayoutID, floats: FloatExclusions) {
        let data: BlockData = self[block: id]
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
        placement.wrap(around: floats, from: y(id))
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
                case .boxEdge(let edge):
                    placeBoxEdge(id, edge, into: &placement)
                }
            }
        })
        profiler.measure("layout.inline.place.finish", {
            placement.finish(in: &self)
        })
        if placement.objectsChanged {
            self[block: id].content.inlineObjects = placement.objects
        }
        profiler.measure("layout.inline.place.parentChildren", {
            setInlineChildrenField(placement.lines, of: id)
        })
        profiler.count("layout.lines.total", by: placement.lines.count)
    }

    mutating private func refreshReusedLine(
        _ line: LayoutID,
        items: [InlineItem]
    ) {
        let children: [LayoutID] = childrenIDs(of: line)
        guard self[line: line].content.inlineWidths.count == children.count else { return }
        var widths: [CGFloat] = self[line: line].content.inlineWidths
        for (index, child) in children.enumerated() where isText(child) {
            let textFragment: TextFragment? = self[text: child].fragment
            guard let fragment: TextFragment = textFragment,
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
            self[text: child].metrics.width = width
            self[text: child].metrics.measured = true
            markField(.font, at: child)
            markField(.width, at: child)
        }
        self[line: line].content.inlineWidths = widths
    }

    mutating private func placeInlineItems(
        _ id: LayoutID,
        plan: [[Int]],
        oldPlan: [[Int]],
        refreshMetrics: Bool
    ) {
        let data: BlockData = self[block: id]
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
                childrenIDs(of: old.line).contains(where: { isText($0) }),
                !used.contains(old.line)
            else { continue }
            reusable[index] = old.line
            used.insert(old.line)
        }
        var free: LinePool = LinePool(oldLines.filter({ !used.contains($0) }))
        let collectsBoxes: Bool = !items.contains(where: { item in
            if case .embed = item { return true }
            return false
        })
        var placement: InlinePlacement = InlinePlacement(
            parent: id,
            reusableLines: [],
            objects: data.content.inlineObjects,
            collectsBoxes: collectsBoxes
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
            if let freeLine: LayoutID = free.take() {
                line = freeLine
            } else {
                line = makeLine(dom: domID(of: id), parent: id, previous: previous)
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
            self[block: id].content.inlineObjects = placement.objects
        }
        setInlineChildrenField(lines, of: id)
        profiler.count("layout.lines.total", by: lines.count)
    }

    private static let inlineFontProperties: Set<StyleProperty> = [
        .fontSize, .fontFamily, .fontWeight, .fontStyle,
    ]

    private func canRefreshFontsOnly(_ id: LayoutID) -> Bool {
        guard !isDirty(.children, at: id),
            self[block: id].changes.childChanges.isEmpty
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

    @discardableResult
    mutating private func refreshInlineItems(_ id: LayoutID, preservingObjects: Bool) -> Bool {
        var data: BlockData = self[block: id]
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
            var items: [InlineItem] = []
            collectItems(id, into: &items)
            data.content.inlineItems = items
            textRuns[id] = TextRun(items: items)
            if !preservingObjects {
                data.content.inlineObjects.removeAll(keepingCapacity: true)
            }
            profiler.count("layout.inline.items.rebuilt", by: items.count)
        }
        if !preservingObjects || data.content.inlineItems.isEmpty {
            data.content.inlineLinePlan = nil
        } else {
            // The items changed size. Keep the old breaks for line reuse only.
            data.content.inlineLinePlan?.fits = nil
        }
        let reusablePlan: Bool = preservingObjects && !data.content.inlineItems.isEmpty
        self[block: id] = data
        let revision: UInt64 = storedInlineContent(id) + 1
        setInlineContent(revision, for: id)
        return reusablePlan
    }

    private func collectLeaves(
        _ n: LayoutDOMView,
        leaves: inout [LayoutDOMView],
        hidden: inout [NodeID]
    ) {
        if n.text != nil {
            leaves.append(n)
            return
        }
        guard let el = n.element else { return }
        if el.tag == "br" || isEmbed(el) {
            leaves.append(n)
            return
        }
        for child in inputs.allChildren(n.id) {
            if inputs.isDisplayNone(child) {
                hidden.append(child)
            } else {
                collectLeaves(domView(child), leaves: &leaves, hidden: &hidden)
            }
        }
    }

    /// The same walk as `inlineLeaves`, but it also marks where each inline
    /// element with padding or border starts and ends. The block's own element
    /// is never an inline box.
    private func collectItems(_ id: LayoutID, into items: inout [InlineItem]) {
        let extraNodes: [LayoutDOMView] = blockExtraNodes(id)
        if !extraNodes.isEmpty {
            for node in extraNodes { appendItems(id, node, boxed: true, into: &items) }
            return
        }
        let hasBlockChild: Bool = domView(id).children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if !hasBlockChild {
            appendItems(id, domView(id), boxed: false, into: &items)
            return
        }
        for child in domView(id).children where child.style.computed.layout.display != .block {
            appendItems(id, child, boxed: true, into: &items)
        }
    }

    private func appendItems(
        _ id: LayoutID,
        _ n: LayoutDOMView,
        boxed: Bool,
        into items: inout [InlineItem]
    ) {
        guard let el = n.element, el.tag != "br", !isEmbed(el) else {
            items.append(contentsOf: makeItems(id, for: n))
            return
        }
        let edges: Bool = boxed && hasInlineBoxEdges(el)
        if edges {
            items.append(.boxEdge(InlineBoxEdge(dom: el.ref.id, side: .start)))
        }
        for child in n.children { appendItems(id, child, boxed: true, into: &items) }
        if edges {
            items.append(.boxEdge(InlineBoxEdge(dom: el.ref.id, side: .end)))
        }
    }

    private func hasInlineBoxEdges(_ el: LayoutElementView) -> Bool {
        let style: ComputedStyle = el.style.computed
        guard style.layout.display == .inline else { return false }
        return style.box.paddingAndBorder != .zero
    }

    /// CSS 2.1 §8.6: an element's start edge is its left one in
    /// left-to-right text and its right one in right-to-left text. Breaking
    /// lines only needs how much room each line gives up; the line decides
    /// which side of the fragment it goes on.
    mutating private func placeBoxEdge(
        _ id: LayoutID,
        _ edge: InlineBoxEdge,
        into placement: inout InlinePlacement
    ) {
        let style: ComputedStyle = inputs.style(edge.dom)
        let edges: EdgeInsets = style.box.paddingAndBorder.scaled(by: zoom(id))
        let rightToLeft: Bool = style.text.direction == .rtl
        switch edge.side {
        case .start:
            placement.openBox(edge.dom, width: rightToLeft ? edges.right : edges.left, in: &self)
        case .end:
            placement.closeBox(edge.dom, width: rightToLeft ? edges.left : edges.right, in: &self)
        }
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
            self[line: placement.currentLine!].content.hasEmbed = true
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
        let wraps: Bool = item.run.whiteSpace.wraps
        let extent: InlineExtent = InlineExtent(ascent: font.ascent, descent: font.descent)
        if wraps {
            placement.dropBelowFloats(toFit: w, extent: extent, blockWidth: width(id))
        }
        let brokeEarly: Bool = {
            if !placement.fits(w, extent: extent, blockWidth: width(id)) && wraps {
                if item.word.contains("\u{00AD}") {
                    let parts: [String] = item.word.components(separatedBy: "\u{00AD}")
                    var chunk: String = ""
                    var breakIdx: Int = -1
                    for (i, part) in parts.dropLast().enumerated() {
                        let candidate: String = chunk + part + "-"
                        if placement.fits(font.measure(candidate), extent: extent, blockWidth: width(id)) {
                            chunk = chunk + part
                            breakIdx = i
                        }
                    }
                    if breakIdx >= 0 {
                        placement.flushText(in: &self)
                        placement.grow(extent)
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
                placement.dropBelowFloats(toFit: w, extent: extent, blockWidth: width(id))
            }
            return false
        }()
        if brokeEarly { return }

        var measuredItem: InlineTextItem = item
        if measuredItem.measuredWidth == nil {
            measuredItem.measuredWidth = measured
        }
        placement.grow(extent)
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
        let w: CGFloat = embedLineWidth(node, available: available, zoom: zoom)
        placement.makeRoom(for: w, extent: embedExtent(node, in: id), blockWidth: available, in: &self)
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
        let w: CGFloat = embedLineWidth(node, available: available, zoom: zoom)
        placement.makeRoom(for: w, extent: embedExtent(node, in: id), blockWidth: available, in: &self)
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
        let w: CGFloat = embedLineWidth(node, available: available, zoom: zoom)
        placement.makeRoom(for: w, extent: embedExtent(node, in: id), blockWidth: available, in: &self)
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
        let w: CGFloat = embedLineWidth(node, available: available, zoom: zoom)
        placement.makeRoom(for: w, extent: embedExtent(node, in: id), blockWidth: available, in: &self)
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
        let w: CGFloat = embedLineWidth(node, available: available, zoom: zoom)
        placement.makeRoom(for: w, extent: embedExtent(node, in: id), blockWidth: available, in: &self)
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
            self[text: id].payload.word == word
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
            kind.matches(self[embed: id])
        else { return nil }
        return id
    }

    // MARK: - Paint

    func blockSelfRect(_ id: LayoutID) -> Rect {
        let padding: EdgeInsets = EdgeInsets(
            top: paintedPadding(id, .paddingTop),
            right: paintedPadding(id, .paddingRight),
            bottom: paintedPadding(id, .paddingBottom),
            left: paintedPadding(id, .paddingLeft)
        )
        return contentRect(id).outset(by: padding).outset(by: blockBorderWidths(id))
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

    @MainActor
    func blockPaintScrollbar(_ id: LayoutID) -> [DisplayOp] {
        let scroll: BlockScroll = self[block: id].scroll
        guard domView(id).style.computed.layout.overflow == .scroll,
            scroll.contentHeight > height(id)
        else { return [] }
        let barWidth: CGFloat = 8
        let ratio: CGFloat = height(id) / scroll.contentHeight
        let barHeight: CGFloat = ratio * height(id)
        let barTop: CGFloat = y(id) + (blockScrollOffset(id) / scroll.contentHeight) * height(id)
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
        let paint: BlockPaint = self[block: id].paint
        if let cachedStyle = paint.style, paint.styleRevision == revision {
            profiler.count("layout.block.style.cache.hit")
            return cachedStyle
        }
        profiler.count("layout.block.style.cache.miss")
        let style: BlockStyle = BlockStyle(style: domView(id).style.computed)
        self[block: id].paint.style = style
        self[block: id].paint.styleRevision = revision
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

    /// The offset lives in the DOM, so no layout can move it back; this layout
    /// only bounds it to the content it produced.
    @MainActor
    func blockScrollOffset(_ id: LayoutID) -> CGFloat {
        guard domView(id).element != nil,
            domView(id).style.computed.layout.overflow == .scroll
        else { return 0 }
        let offset: CGFloat = dom.side.scrollOffsets[domID(of: id)] ?? 0
        return min(offset, blockScrollRange(id))
    }

    func blockScrollRange(_ id: LayoutID) -> CGFloat {
        return max(0, blockContentHeight(id) - height(id))
    }

    func blockContentHeight(_ id: LayoutID) -> CGFloat {
        return self[block: id].scroll.contentHeight
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
    var boxes: InlineBoxPlacement = InlineBoxPlacement()
}

private struct PendingInlineBox {
    let dom: NodeID
    let width: CGFloat
}

/// Inline elements with padding or border while the block fills its lines.
/// An element's start waits for its first child, so a start right before a
/// line break moves to the next line together with that child. A line with
/// no such element records no events at all.
private struct InlineBoxPlacement {
    var events: [InlineFlowEvent] = []
    var pending: [PendingInlineBox] = []
    var open: [NodeID] = []
    var unrecordedChildren: Int = 0

    var pendingWidth: CGFloat {
        return pending.reduce(0, { $0 + $1.width })
    }

    mutating func noteChild() {
        guard !events.isEmpty || !pending.isEmpty || !open.isEmpty else {
            unrecordedChildren += 1
            return
        }
        commitPending()
        events.append(.child)
    }

    mutating func close(_ dom: NodeID, width: CGFloat) {
        if pending.contains(where: { $0.dom == dom }) {
            commitPending()
        }
        recordEarlierChildren()
        events.append(.close(dom: dom, width: width, closes: true))
        if let index: Int = open.lastIndex(of: dom) {
            open.remove(at: index)
        }
    }

    /// Ends the line inside every element still open; the next line starts
    /// inside them again, without their start edges.
    mutating func breakLine() -> [InlineFlowEvent] {
        if !open.isEmpty {
            recordEarlierChildren()
        }
        for dom in open.reversed() {
            events.append(.close(dom: dom, width: 0, closes: false))
        }
        let finished: [InlineFlowEvent] = events
        events = open.map({ .open(dom: $0, width: 0, opens: false) })
        unrecordedChildren = 0
        return finished
    }

    private mutating func commitPending() {
        guard !pending.isEmpty else { return }
        recordEarlierChildren()
        for box in pending {
            events.append(.open(dom: box.dom, width: box.width, opens: true))
            open.append(box.dom)
        }
        pending.removeAll(keepingCapacity: true)
    }

    private mutating func recordEarlierChildren() {
        guard unrecordedChildren > 0 else { return }
        events.insert(contentsOf: Array(repeating: InlineFlowEvent.child, count: unrecordedChildren), at: 0)
        unrecordedChildren = 0
    }
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
    var boxes: [InlineBox] = []
}

private struct InlinePlacementState {
    var lines: [LayoutID] = []
    var currentLine: LayoutID? = nil
    var content: InlineLineContent = InlineLineContent()
    var cursor: LineCursor = LineCursor()
}

/// The line being filled: where its next item goes, its band, and the floats
/// that may shorten it.
private struct LineCursor {
    var x: CGFloat = 0
    var band: LineBand = LineBand()
    var floats: FloatExclusions = .none
}

/// `top` is the line's top before any drop below a float; `extent` grows with
/// every item, and `insets` always fit the band that tall.
private struct LineBand {
    var top: CGFloat = 0
    var insets: LineFloatInsets = .zero
    var extent: InlineExtent = .zero
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
    private let collectsBoxes: Bool

    init(
        parent: LayoutID,
        reusableLines: [LayoutID],
        objects: [Int: LayoutID],
        collectsBoxes: Bool = false
    ) {
        self.context = InlinePlacementContext(parent: parent, objects: objects)
        self.pool = LinePool(reusableLines)
        self.collectsBoxes = collectsBoxes
    }

    var lines: [LayoutID] { state.lines }
    var currentLine: LayoutID? { state.currentLine }
    var children: [LayoutID] { state.content.children }
    var buildsBoxes: Bool { collectsBoxes }
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
        get { state.cursor.x }
        set { state.cursor.x = newValue }
    }

    func lineWidth(_ blockWidth: CGFloat) -> CGFloat {
        return blockWidth - state.cursor.band.insets.left - state.cursor.band.insets.right
    }

    mutating func wrap(around floats: FloatExclusions, from top: CGFloat) {
        state.cursor.floats = floats
        state.cursor.band.top = top
    }

    /// Whether an item fits on the line once the line has grown to hold it: a
    /// taller line can reach a float its current band misses.
    func fits(_ width: CGFloat, extent: InlineExtent, blockWidth: CGFloat) -> Bool {
        guard !state.cursor.floats.isEmpty else { return cursorX + width <= lineWidth(blockWidth) }
        let band: LineBand = state.cursor.band
        let insets: LineFloatInsets = state.cursor.floats.insets(
            top: band.top,
            gap: band.insets.gap,
            height: band.extent.union(extent).height
        )
        return cursorX + width <= blockWidth - insets.left - insets.right
    }

    mutating func grow(_ extent: InlineExtent) {
        state.cursor.band.extent = state.cursor.band.extent.union(extent)
        guard !state.cursor.floats.isEmpty else { return }
        let band: LineBand = state.cursor.band
        state.cursor.band.insets = state.cursor.floats.insets(
            top: band.top,
            gap: band.insets.gap,
            height: band.extent.height
        )
    }

    /// Keeps the old rule of ending a line that cannot take the item, except
    /// that an empty line beside floats moves below them instead, then grows
    /// the line to hold the item.
    mutating func makeRoom(
        for width: CGFloat,
        extent: InlineExtent,
        blockWidth: CGFloat,
        in tree: inout LayoutTree
    ) {
        let dropsInstead: Bool = !state.cursor.floats.isEmpty && isLineEmpty
        if !dropsInstead, !fits(width, extent: extent, blockWidth: blockWidth) {
            endLine(in: &tree)
        }
        dropBelowFloats(toFit: width, extent: extent, blockWidth: blockWidth)
        grow(extent)
    }

    /// CSS 2.1 §9.5: a shortened line box too small for any content moves down
    /// until some content fits or no more floats are beside it.
    mutating func dropBelowFloats(toFit width: CGFloat, extent: InlineExtent, blockWidth: CGFloat) {
        guard !state.cursor.floats.isEmpty, isLineEmpty else { return }
        let floats: FloatExclusions = state.cursor.floats
        let height: CGFloat = state.cursor.band.extent.union(extent).height
        while !fits(width, extent: extent, blockWidth: blockWidth),
            let next: CGFloat = floats.nextTop(
                after: state.cursor.band.top + state.cursor.band.insets.gap,
                height: height
            )
        {
            let top: CGFloat = state.cursor.band.top
            state.cursor.band.insets = floats.insets(top: top, gap: next - top, height: height)
        }
    }

    private var isLineEmpty: Bool {
        return state.content.children.isEmpty
            && state.content.pending == nil
            && state.content.boxes.isEmpty
    }

    private mutating func startCursor() {
        state.cursor.x = context.boxes.pendingWidth
        state.cursor.band.extent = .zero
        state.cursor.band.insets = state.cursor.floats.insets(top: state.cursor.band.top, gap: 0, height: 0)
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
                dom: tree.domID(of: context.parent),
                parent: context.parent,
                previous: previous
            )
            previousChanged = true
            state.content = InlineLineContent()
        }
        startCursor()
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
        startCursor()
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
        if collectsBoxes {
            state.content.boxes.append(
                InlineBox(
                    dom: pending.style.node,
                    fragment: fragment,
                    geometry: InlineBoxGeometry(x: 0, y: 0, width: pending.width),
                    text: InlineBoxText(
                        payload: TextPayload(word: "", display: nil, fontOverride: nil),
                        font: pending.style.font,
                        ascent: pending.style.font.ascent,
                        descent: pending.style.font.descent
                    )
                )
            )
            context.boxes.noteChild()
            state.content.widths.append(pending.width)
            state.content.pending = nil
            return
        }
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
            tree[text: text].fragment = fragment
            tree[text: text].payload.word = ""
            tree[text: text].payload.display = nil
            tree[text: text].metrics.width = pending.width
            tree[text: text].metrics.measured = true
        }
        tree.setFontAndPrevious(
            pending.style.font,
            previous: previous,
            measuredWidth: nil,
            for: text
        )
        context.boxes.noteChild()
        state.content.children.append(text)
        state.content.widths.append(pending.width)
        state.content.pending = nil
    }

    mutating func append(_ child: LayoutID, width: CGFloat) {
        context.boxes.noteChild()
        state.content.children.append(child)
        state.content.widths.append(width)
    }

    mutating func openBox(_ dom: NodeID, width: CGFloat, in tree: inout LayoutTree) {
        flushText(in: &tree)
        context.boxes.pending.append(PendingInlineBox(dom: dom, width: width))
        state.cursor.x += width
    }

    mutating func closeBox(_ dom: NodeID, width: CGFloat, in tree: inout LayoutTree) {
        flushText(in: &tree)
        context.boxes.close(dom, width: width)
        state.cursor.x += width
    }

    private mutating func commitLine(_ line: LayoutID, in tree: inout LayoutTree) {
        tree[line: line].content.inlineWidths = state.content.widths
        tree[line: line].content.boxes = state.content.boxes
        let band: LineBand = state.cursor.band
        if tree[line: line].placement.floatInsets != band.insets {
            tree[line: line].placement.floatInsets = band.insets
            tree.markField(.x, at: line)
            tree.markField(.y, at: line)
            tree.markField(.width, at: line)
        }
        if !state.cursor.floats.isEmpty {
            state.cursor.band.top += band.insets.gap + band.extent.height
        }
        let events: [InlineFlowEvent] = context.boxes.breakLine()
        if tree[line: line].inlineBoxes.events != events {
            tree[line: line].inlineBoxes.events = events
            // The same children can sit at new positions when only the
            // padding or border around them changed.
            tree.markField(.x, at: line)
        }
        profiler.measure("layout.inline.place.lineChildren", {
            tree.setLineChildrenField(
                state.content.children,
                of: line,
                previousChanged: previousChanged
            )
        })
    }
}
