import CoreGraphics

// MARK: - LineLayoutPass

extension LayoutTree {
    mutating func makeLine(
        dom: NodeID,
        parent: LayoutID,
        previous: LayoutID?
    ) -> LayoutID {
        let id: LayoutID = append(
            kind: .line(LineData()),
            dom: dom,
            parent: parent,
            previous: previous
        )
        setChildrenClean([], of: id)
        setFieldClean(.ascent, 0, for: id)
        setFieldClean(.descent, 0, for: id)
        for field in [LayoutField.zoom, .width, .x, .y, .height] {
            markUsed(field, at: id)
        }
        markAncestorsDirty(from: id)
        return id
    }

    @discardableResult
    mutating func resetLine(_ id: LayoutID, previous: LayoutID?) -> Bool {
        let oldPrevious: LayoutID? = previousID(of: id)
        var data: LineData = LineData()
        if case .line = self[node: id].kind {
            // The line paint cache is keyed by this generation.
            data.paint.generation = self[line: id].paint.generation + 1
        }
        setKind(.line(data), at: id)
        setPrevious(previous, of: id)
        for field in [
            LayoutField.zoom,
            .width,
            .x,
            .y,
            .height,
            .ascent,
            .descent,
        ] {
            markField(field, at: id)
        }
        return oldPrevious != previous
    }

    /// The vertical-only path then shifts `inlineYOffset` instead of
    /// writing a position for every text child.
    @discardableResult
    mutating func reuseLine(_ id: LayoutID, previous: LayoutID?) -> Bool {
        let oldPrevious: LayoutID? = previousID(of: id)
        self[line: id].paint.generation += 1
        // The block's inline-content revision can advance (font refresh)
        // while its lines are reused; the boxes stay valid but the revision
        // they were built for must follow, or `currentInlineBoxes` rejects
        // them and paint falls back to the absent text children.
        if let block: LayoutID = parentID(of: id), let revision: UInt64 = boxRevision(block) {
            self[line: id].paint.boxRevision = revision
        }
        setPrevious(previous, of: id)
        for field in [LayoutField.width, .y] {
            markField(field, at: id)
        }
        return oldPrevious != previous
    }

    func lineLayoutNeeded(_ id: LayoutID) -> Bool {
        if hasDirtyDescendants(at: id) {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: FieldState = self[node: id].state.fields.state
        return state.isDirty(.zoom) || state.isDirty(.x) || state.isDirty(.y)
            || state.isDirty(.width) || state.isDirty(.height)
            || state.isDirty(.ascent) || state.isDirty(.descent)
    }

    mutating func layoutLine(_ id: LayoutID) {
        guard lineLayoutNeeded(id) else { return }
        defer { setDirtyDescendants(false, at: id) }
        let xWasDirty: Bool = isDirty(.x, at: id)
        let yWasDirty: Bool = isDirty(.y, at: id)
        let zoomWasDirty: Bool = isDirty(.zoom, at: id)
        let children: [LayoutID] = childrenIDs(of: id)
        let declaredChildCount: Int = self[line: id].placement.declaredInlineChildCount
        let childCountChanged: Bool = children.count != declaredChildCount
        var childWidthChanged: Bool = false
        for child in children where isDirty(.width, at: child) {
            childWidthChanged = true
            break
        }
        if children.count != self[line: id].paint.paintedChildCount {
            self[line: id].paint.generation += 1
            self[line: id].paint.paintedChildCount = children.count
        }
        let parent: LayoutID = parentID(of: id)!
        let previous: LayoutID? = previousID(of: id)
        var lineY: CGFloat = y(parent)
        if let previous {
            lineY = y(previous) + height(previous)
        }
        setFrame(
            (
                zoom: zoom(parent),
                x: x(parent),
                y: lineY,
                width: width(parent)
            ),
            for: id
        )

        if childCountChanged {
            self[line: id].placement.declaredInlineChildCount = children.count
        }

        let widthMovesChildren: Bool = self[line: id].content.centered
            || inputs.style(domID(of: id)).text.direction == .rtl
        let needsPlacement: Bool = xWasDirty || yWasDirty || childCountChanged
            || childWidthChanged
            || isDirty(.ascent, at: id)
            || isDirty(.descent, at: id)
            || isDirty(.height, at: id)
            || isDirty(.children, at: id)
            || widthMovesChildren

        var textOnly: Bool = true
        for child in children where !isText(child) {
            textOnly = false
            break
        }
        let hasBoxes: Bool = !self[line: id].content.boxes.isEmpty
        // Only lines backed by text children may take the child fast path.
        // A value line has no children; it keeps its text in `content.boxes`,
        // and this path used to rebuild those boxes from the empty child list.
        let verticalOnly: Bool = yWasDirty && !xWasDirty && !zoomWasDirty
            && !childCountChanged && !childWidthChanged && !widthMovesChildren
            && !isDirty(.ascent, at: id)
            && !isDirty(.descent, at: id)
            && !isDirty(.height, at: id)
            && !isDirty(.children, at: id)
            && textOnly && !children.isEmpty
            && self[line: id].placement.childOriginY != nil

        if verticalOnly, let childOriginY: CGFloat = self[line: id].placement.childOriginY {
            profiler.count("layout.line.place.verticalOnly")
            let verticalSpan: ProfileSpan = profiler.begin("layout.line.place.vertical")
            self[line: id].placement.inlineYOffset = y(id) - childOriginY
            profiler.end(verticalSpan)
            if self[line: id].content.boxes.isEmpty {
                syncInlineBoxes(id)
            } else {
                followBoxRevision(id)
            }
            return
        }

        guard needsPlacement else {
            profiler.count("layout.line.place.skipped")
            return
        }

        for child in children { layout(child) }

        profiler.count("layout.line.place.placed")
        let placeSpan: ProfileSpan = profiler.begin("layout.line.place")
        placeLineChildren(id, children: children, hasBoxes: hasBoxes)
        profiler.end(placeSpan)
    }

    mutating private func placeLineChildren(_ id: LayoutID, children: [LayoutID], hasBoxes: Bool) {
        if hasBoxes, children.isEmpty {
            layoutLineBoxes(id)
            return
        }
        guard !children.isEmpty else {
            setField(.ascent, 0, for: id)
            setField(.descent, 0, for: id)
            setField(.height, 0, for: id)
            return
        }

        let inlineChildren: [LayoutID] = children.filter({ isText($0) || isEmbed($0) })
        guard !inlineChildren.isEmpty else {
            setField(.height, 0, for: id)
            return
        }

        var maxAscent: CGFloat = 0
        var maxDescent: CGFloat = 0
        for child in inlineChildren {
            maxAscent = max(maxAscent, ascent(child))
            maxDescent = max(maxDescent, descent(child))
        }
        setField(.ascent, maxAscent, for: id)
        setField(.descent, maxDescent, for: id)

        var nextX: CGFloat = x(id)
        var previousFont: BrowserFont? = nil
        let baseline: CGFloat = y(id) + ascent(id)
        func place(_ index: Int) {
            let child: LayoutID = inlineChildren[index]
            if let previousFont, isEmbed(child) {
                nextX += previousFont.spaceWidth
            }
            let edges: EdgeInsets = inlineEdges(child)
            let boxTop: CGFloat = inputs.tag(domID(of: child)) == "sup"
                ? baseline - maxAscent
                : baseline - ascent(child)
            setPosition(x: nextX + edges.left, y: boxTop + edges.top, for: child)
            nextX += inlineWidth(id, index: index, child: child)
            previousFont = font(child)
        }

        let events: [InlineFlowEvent] = self[line: id].inlineBoxes.events
        var fragments: [InlineBoxFragment] = []
        if events.isEmpty {
            for index in inlineChildren.indices { place(index) }
        } else {
            var open: [OpenInlineBox] = []
            var index: Int = 0
            // A word's width carries the space after it. That space belongs
            // after the element's end edge, not inside its box.
            var trailingSpace: CGFloat = 0
            for event in events {
                switch event {
                case .child:
                    guard index < inlineChildren.count else { continue }
                    place(index)
                    trailingSpace = isText(inlineChildren[index]) ? font(inlineChildren[index]).spaceWidth : 0
                    index += 1
                case .open(let dom, let width, let opens):
                    open.append(OpenInlineBox(dom: dom, left: nextX, opens: opens))
                    nextX += width
                    trailingSpace = 0
                case .close(let dom, let width, let closes):
                    nextX += width
                    guard let start: Int = open.lastIndex(where: { $0.dom == dom }) else { continue }
                    let box: OpenInlineBox = open.remove(at: start)
                    let right: CGFloat = max(box.left, nextX - trailingSpace)
                    fragments.append(inlineBoxFragment(id, box, right: right, closes: closes))
                }
            }
        }
        if self[line: id].inlineBoxes.fragments != fragments {
            self[line: id].inlineBoxes.fragments = fragments
            self[line: id].paint.generation += 1
        }

        for child in children where !isText(child) && !childrenIDs(of: child).isEmpty {
            layout(child)
        }

        if inputs.style(domID(of: id)).text.direction == .rtl {
            let usedWidth: CGFloat = contentWidth(id)
            shiftChildren(id, by: width(id) - usedWidth)
        }

        if self[line: id].content.centered {
            let usedWidth: CGFloat = contentWidth(id)
            shiftChildren(id, by: (width(id) - usedWidth) / 2)
        }

        setField(.height, ascent(id) + descent(id), for: id)
        let originY: CGFloat = y(id)
        self[line: id].placement.childOriginY = originY
        self[line: id].placement.inlineYOffset = 0
        syncInlineBoxes(id)
    }

    /// Shadow values for the fragment-node migration. Paint and hit-test still
    /// read the text children until the value path is complete.
    mutating private func syncInlineBoxes(_ id: LayoutID) {
        guard collectsInlineBoxes else { return }
        guard !self[line: id].content.hasEmbed else { return }
        let children: [LayoutID] = childrenIDs(of: id)
        // A value line owns its text as boxes and has no text children;
        // syncing from the child list would erase that text.
        if children.isEmpty, !self[line: id].content.boxes.isEmpty {
            return
        }
        profiler.count("layout.line.boxes.built")
        var boxes: [InlineBox] = []
        boxes.reserveCapacity(children.count)
        for child in children where isText(child) {
            let data: TextData = self[text: child]
            boxes.append(
                InlineBox(
                    dom: domID(of: child),
                    fragment: data.fragment,
                    geometry: InlineBoxGeometry(
                        x: x(child),
                        y: textAbsoluteY(child) - y(id),
                        width: textTextWidth(child)
                    ),
                    text: InlineBoxText(
                        payload: data.payload,
                        font: font(child),
                        ascent: ascent(child),
                        descent: descent(child)
                    )
                )
            )
        }
        followBoxRevision(id)
        guard self[line: id].content.boxes != boxes else { return }
        self[line: id].content.boxes = boxes
        self[line: id].paint.generation += 1
    }

    /// Points the line's boxes at the block's current inline-content revision,
    /// so `currentInlineBoxes` keeps accepting boxes that are still valid.
    mutating private func followBoxRevision(_ id: LayoutID) {
        guard collectsInlineBoxes, !self[line: id].content.hasEmbed,
            let block: LayoutID = parentID(of: id),
            let revision: UInt64 = boxRevision(block),
            self[line: id].paint.boxRevision != revision
        else { return }
        self[line: id].paint.boxRevision = revision
    }

    mutating private func shiftChildren(_ id: LayoutID, by offset: CGFloat) {
        guard offset != 0 else { return }
        self[line: id].paint.generation += 1
        let children: [LayoutID] = childrenIDs(of: id)
        let shifted: [CGFloat] = children.map({ x($0) + offset })

        for (child, x) in zip(children, shifted) {
            setField(.x, x, for: child)
        }
        self[line: id].inlineBoxes.fragments = self[line: id].inlineBoxes.fragments.map({ fragment in
            InlineBoxFragment(
                dom: fragment.dom,
                rect: fragment.rect.translated(dx: offset, dy: 0),
                opens: fragment.opens,
                closes: fragment.closes
            )
        })
    }

    /// CSS 2.1 §10.6.1: an inline box's vertical padding and border sit
    /// around its content area, the height its own font gives it, and do not
    /// make the line taller.
    private func inlineBoxFragment(
        _ id: LayoutID,
        _ box: OpenInlineBox,
        right: CGFloat,
        closes: Bool
    ) -> InlineBoxFragment {
        let font: BrowserFont = fontFor(box.dom, zoom: zoom(id))
        let edges: EdgeInsets = inputs.style(box.dom).box.paddingAndBorder.scaled(by: zoom(id))
        let baseline: CGFloat = ascent(id)
        return InlineBoxFragment(
            dom: box.dom,
            rect: Rect(
                left: box.left - x(id),
                top: baseline - font.ascent - edges.top,
                right: right - x(id),
                bottom: baseline + font.descent + edges.bottom
            ),
            opens: box.opens,
            closes: closes
        )
    }

    private func inlineWidth(_ id: LayoutID, index: Int, child: LayoutID) -> CGFloat {
        let widths: [CGFloat] = self[line: id].content.inlineWidths
        if index < widths.count {
            return widths[index]
        }
        return width(child) + inlineEdges(child).horizontal
    }

    /// Text has no box of its own; an embed's content sits inside its padding
    /// and border.
    private func inlineEdges(_ child: LayoutID) -> EdgeInsets {
        return isEmbed(child) ? embedEdges(child) : .zero
    }

    private func contentWidth(_ id: LayoutID) -> CGFloat {
        let inline: [LayoutID] = childrenIDs(of: id).filter({ isText($0) || isEmbed($0) })
        guard let last: LayoutID = inline.last else { return 0 }
        let trailing: CGFloat = inlineWidth(id, index: inline.count - 1, child: last)
        let childEnd: CGFloat = x(last) - inlineEdges(last).left + trailing - x(id)
        let boxEnd: CGFloat = self[line: id].inlineBoxes.fragments.map(\.rect.right).max() ?? 0
        return max(childEnd, boxEnd)
    }

    func lineCanCachePaint(_ id: LayoutID) -> Bool {
        return !self[line: id].content.hasEmbed && self[line: id].inlineBoxes.fragments.isEmpty
    }

    private func boxRevision(_ id: LayoutID) -> UInt64? {
        guard isBlock(id), isUsed(.inlineContent, at: id),
            !isDirty(.inlineContent, at: id)
        else { return nil }
        return inlineContent(id)
    }

    mutating private func layoutLineBoxes(_ id: LayoutID) {
        let data: LineData = self[line: id]
        guard !data.content.boxes.isEmpty else { return }
        let maxAscent: CGFloat = data.content.boxes.map({ $0.text.ascent }).max() ?? 0
        let maxDescent: CGFloat = data.content.boxes.map({ $0.text.descent }).max() ?? 0
        setField(.ascent, maxAscent, for: id)
        setField(.descent, maxDescent, for: id)
        let baseline: CGFloat = maxAscent
        let usedWidth: CGFloat = data.content.boxes.reduce(0) { $0 + $1.geometry.width }
        var cursorX: CGFloat = x(id)
        if inputs.style(domID(of: id)).text.direction == .rtl {
            cursorX += width(id) - usedWidth
        }
        if data.content.centered {
            cursorX += (width(id) - usedWidth) / 2
        }
        var boxes: [InlineBox] = data.content.boxes
        for index in boxes.indices {
            let box: InlineBox = boxes[index]
            boxes[index] = InlineBox(
                dom: box.dom,
                fragment: box.fragment,
                geometry: InlineBoxGeometry(
                    x: cursorX,
                    y: baseline - box.text.ascent,
                    width: box.geometry.width
                ),
                text: box.text
            )
            cursorX += box.geometry.width
        }
        let revision: UInt64? = parentID(of: id).flatMap({ boxRevision($0) })
        let originY: CGFloat = y(id)
        self[line: id].content.inlineWidths = boxes.map({ $0.geometry.width })
        self[line: id].content.boxes = boxes
        if let revision {
            self[line: id].paint.boxRevision = revision
        }
        self[line: id].paint.generation += 1
        self[line: id].placement.childOriginY = originY
        self[line: id].placement.inlineYOffset = 0
        setField(.height, maxAscent + maxDescent, for: id)
    }

    /// Boxes are only current when they still describe the live text
    /// children. Incremental text edits can replace a child without forcing a
    /// fresh line placement, in which case callers must fall back to nodes.
    func currentInlineBoxes(_ id: LayoutID) -> [InlineBox]? {
        let data: LineData = self[line: id]
        guard !data.content.hasEmbed, !data.content.boxes.isEmpty else { return nil }
        let block: LayoutID? = parentID(of: id)
        guard let block, let revision: UInt64 = boxRevision(block),
            data.paint.boxRevision == revision
        else { return nil }
        let inline: [LayoutID] = childrenIDs(of: id).filter({ isText($0) || isEmbed($0) })
        let textIndices: [Int] = inline.indices.filter({ isText(inline[$0]) })
        if textIndices.isEmpty { return data.content.boxes }
        guard textIndices.count == data.content.boxes.count else { return nil }
        for (box, index) in zip(data.content.boxes, textIndices) {
            let child: LayoutID = inline[index]
            let text: TextData = self[text: child]
            guard box.dom == domID(of: child),
                box.fragment == text.fragment,
                box.geometry.x == x(child),
                box.geometry.y + y(id) == textAbsoluteY(child),
                box.geometry.width == textTextWidth(child, at: index, in: id),
                readsTextRun(box) || inlineText(box) == textString(child)
            else { return nil }
        }
        return data.content.boxes
    }

    private func readsTextRun(_ box: InlineBox) -> Bool {
        guard let fragment: TextFragment = box.fragment else { return false }
        return textRuns[fragment.block] != nil
    }
}

// MARK: - OpenInlineBox

/// An inline element whose start the line has passed but whose end it has not.
private struct OpenInlineBox {
    let dom: NodeID
    let left: CGFloat
    let opens: Bool
}
