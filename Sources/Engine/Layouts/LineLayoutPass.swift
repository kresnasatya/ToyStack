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

    @discardableResult
    mutating func reuseLine(_ id: LayoutID, previous: LayoutID?) -> Bool {
        let oldPrevious: LayoutID? = previousID(of: id)
        self[line: id].paint.generation += 1
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
        let insets: LineFloatInsets = self[line: id].placement.floatInsets
        var lineY: CGFloat = y(parent)
        if let previous {
            lineY = y(previous) + height(previous)
        }
        setFrame(
            (
                zoom: zoom(parent),
                x: x(parent) + insets.left,
                y: lineY + insets.gap,
                width: width(parent) - insets.left - insets.right
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
        let baseline: CGFloat = y(id) + ascent(id)
        func spaceAfter(_ index: Int) -> CGFloat {
            let child: LayoutID = inlineChildren[index]
            if isText(child) { return font(child).spaceWidth }
            guard index + 1 < inlineChildren.count else { return 0 }
            let next: LayoutID = inlineChildren[index + 1]
            if isText(next) { return font(next).spaceWidth }
            return surroundingTextFont(of: domID(of: next), zoom: zoom(id)).spaceWidth
        }
        func place(_ index: Int) {
            let child: LayoutID = inlineChildren[index]
            let edges: EdgeInsets = inlineEdges(child)
            let boxTop: CGFloat = inputs.tag(domID(of: child)) == "sup"
                ? baseline - maxAscent
                : baseline - ascent(child)
            setPosition(x: nextX + edges.left, y: boxTop + edges.top, for: child)
            nextX += inlineWidth(id, index: index, child: child)
            if isEmbed(child) {
                nextX += spaceAfter(index)
            }
        }

        let events: [InlineFlowEvent] = self[line: id].inlineBoxes.events
        var fragments: [InlineBoxFragment] = []
        if events.isEmpty {
            for index in inlineChildren.indices { place(index) }
        } else {
            var open: [OpenInlineBox] = []
            var index: Int = 0
            var trailingSpace: CGFloat = 0
            for (position, event) in events.enumerated() {
                switch event {
                case .child:
                    guard index < inlineChildren.count else { continue }
                    place(index)
                    trailingSpace = spaceAfter(index)
                    index += 1
                case .open(let dom, let width, let opens):
                    let end: CGFloat = closingWidth(of: dom, after: position, in: events)
                    let rightToLeft: Bool = inputs.style(dom).text.direction == .rtl
                    open.append(OpenInlineBox(
                        dom: dom,
                        left: nextX,
                        rightEdge: rightToLeft ? width : end,
                        opens: opens
                    ))
                    nextX += rightToLeft ? end : width
                    trailingSpace = 0
                case .close(let dom, _, let closes):
                    guard let start: Int = open.lastIndex(where: { $0.dom == dom }) else { continue }
                    let box: OpenInlineBox = open.remove(at: start)
                    nextX += box.rightEdge
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
            let usedWidth: CGFloat = contentWidth(id, trimsEndSpace: false)
            shiftChildren(id, by: width(id) - usedWidth)
        }

        if self[line: id].content.centered {
            shiftChildren(id, by: (width(id) - contentWidth(id, trimsEndSpace: true)) / 2)
        }

        setField(.height, ascent(id) + descent(id), for: id)
        let originY: CGFloat = y(id)
        self[line: id].placement.childOriginY = originY
        self[line: id].placement.inlineYOffset = 0
        syncInlineBoxes(id)
    }

    mutating private func syncInlineBoxes(_ id: LayoutID) {
        guard collectsInlineBoxes else { return }
        guard !self[line: id].content.hasEmbed else { return }
        let children: [LayoutID] = childrenIDs(of: id)
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

    private func closingWidth(of dom: NodeID, after position: Int, in events: [InlineFlowEvent]) -> CGFloat {
        for event in events[(position + 1)...] {
            if case .close(let closing, let width, _) = event, closing == dom {
                return width
            }
        }
        return 0
    }

    private func inlineWidth(_ id: LayoutID, index: Int, child: LayoutID) -> CGFloat {
        let widths: [CGFloat] = self[line: id].content.inlineWidths
        if index < widths.count {
            return widths[index]
        }
        return width(child) + inlineEdges(child).horizontal
    }

    private func inlineEdges(_ child: LayoutID) -> EdgeInsets {
        return isEmbed(child) ? embedEdges(child) : .zero
    }

    /// With `trimsEndSpace`, CSS Text 3 §4.1.2 applies: the space after the
    /// line's last word is removed, so it does not pull centered words left.
    private func contentWidth(_ id: LayoutID, trimsEndSpace: Bool) -> CGFloat {
        let inline: [LayoutID] = childrenIDs(of: id).filter({ isText($0) || isEmbed($0) })
        guard let last: LayoutID = inline.last else { return 0 }
        var trailing: CGFloat = inlineWidth(id, index: inline.count - 1, child: last)
        if trimsEndSpace, isText(last) {
            trailing -= font(last).spaceWidth
        }
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

private struct OpenInlineBox {
    let dom: NodeID
    let left: CGFloat
    let rightEdge: CGFloat
    let opens: Bool
}
