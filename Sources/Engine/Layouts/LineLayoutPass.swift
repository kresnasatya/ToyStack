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
        if case .line(let old) = node(id).kind {
            // The line paint cache is keyed by this generation.
            data.paint.generation = old.paint.generation + 1
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

    /// Keeps the line's placement data when only its frame moves. The
    /// vertical-only path then shifts `inlineYOffset` instead of writing a
    /// position for every text child.
    @discardableResult
    mutating func reuseLine(_ id: LayoutID, previous: LayoutID?) -> Bool {
        let oldPrevious: LayoutID? = previousID(of: id)
        var data: LineData = lineData(id)
        data.paint.generation += 1
        setKind(.line(data), at: id)
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
        let state: LayoutFieldStore = node(id).state.fields
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
        var data: LineData = lineData(id)
        let childCountChanged: Bool = children.count != data.placement.declaredInlineChildCount
        var childWidthChanged: Bool = false
        for child in children where isDirty(.width, at: child) {
            childWidthChanged = true
            break
        }
        if children.count != data.paint.paintedChildCount {
            data.paint.generation += 1
            data.paint.paintedChildCount = children.count
            setKind(.line(data), at: id)
        }
        let parent: LayoutID = parentID(of: id)!
        let previous: LayoutID? = previousID(of: id)
        let lineY: CGFloat = previous.map({ y($0) + height($0) }) ?? y(parent)
        setFrame(
            (
                zoom: zoom(parent),
                x: x(parent),
                y: lineY,
                width: width(parent)
            ),
            for: id
        )

        if children.count != data.placement.declaredInlineChildCount {
            var updated: LineData = lineData(id)
            updated.placement.declaredInlineChildCount = children.count
            setKind(.line(updated), at: id)
        }

        let widthMovesChildren: Bool = lineData(id).content.centered
            || inputs.style(domID(of: id)).text.direction == .rtl
        let needsPlacement: Bool = xWasDirty || yWasDirty || childCountChanged
            || childWidthChanged
            || isDirty(.ascent, at: id)
            || isDirty(.descent, at: id)
            || isDirty(.height, at: id)
            || isDirty(.children, at: id)
            || widthMovesChildren

        let textOnly: Bool = children.allSatisfy({ isText($0) })
        let hasBoxes: Bool = !lineData(id).content.boxes.isEmpty
        let verticalOnly: Bool = yWasDirty && !xWasDirty && !zoomWasDirty
            && !childCountChanged && !childWidthChanged && !widthMovesChildren
            && !isDirty(.ascent, at: id)
            && !isDirty(.descent, at: id)
            && !isDirty(.height, at: id)
            && !isDirty(.children, at: id)
            && textOnly && lineData(id).placement.childOriginY != nil

        if verticalOnly, let childOriginY: CGFloat = lineData(id).placement.childOriginY {
            profiler.count("layout.line.place.verticalOnly")
            profiler.measure("layout.line.place.vertical", {
                var updated: LineData = lineData(id)
                updated.placement.inlineYOffset = y(id) - childOriginY
                setKind(.line(updated), at: id)
            })
            syncInlineBoxes(id)
            return
        }

        guard needsPlacement else {
            profiler.count("layout.line.place.skipped")
            return
        }

        for child in children { layout(child) }

        profiler.count("layout.line.place.placed")
        profiler.measure("layout.line.place", {
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
            for (index, child) in inlineChildren.enumerated() {
                if let previousFont, isEmbed(child) {
                    nextX += previousFont.spaceWidth
                }
                let childY: CGFloat = inputs.tag(domID(of: child)) == "sup"
                    ? baseline - maxAscent
                    : baseline - ascent(child)
                setPosition(x: nextX, y: childY, for: child)
                nextX += inlineWidth(id, index: index, child: child)
                previousFont = font(child)
            }

            for child in children where !isText(child) && !childrenIDs(of: child).isEmpty {
                layout(child)
            }

            if inputs.style(domID(of: id)).text.direction == .rtl {
                let usedWidth: CGFloat = contentWidth(id)
                shiftChildren(id, by: width(id) - usedWidth)
            }

            if lineData(id).content.centered {
                let usedWidth: CGFloat = contentWidth(id)
                shiftChildren(id, by: (width(id) - usedWidth) / 2)
            }

            setField(.height, ascent(id) + descent(id), for: id)
            var updated: LineData = lineData(id)
            updated.placement.childOriginY = y(id)
            updated.placement.inlineYOffset = 0
            setKind(.line(updated), at: id)
            syncInlineBoxes(id)
        })
    }

    /// Shadow values for the fragment-node migration. Paint and hit-test still
    /// read the text children until the value path is complete.
    mutating private func syncInlineBoxes(_ id: LayoutID) {
        guard collectsInlineBoxes else { return }
        guard !lineData(id).content.hasEmbed else { return }
        let children: [LayoutID] = childrenIDs(of: id)
        var boxes: [InlineBox] = []
        boxes.reserveCapacity(children.count)
        for child in children where isText(child) {
            let data: TextData = textData(child)
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
        var line: LineData = lineData(id)
        if let block: LayoutID = parentID(of: id), let revision: UInt64 = boxRevision(block) {
            line.paint.boxRevision = revision
        }
        guard line.content.boxes != boxes else {
            setKind(.line(line), at: id)
            return
        }
        line.content.boxes = boxes
        line.paint.generation += 1
        setKind(.line(line), at: id)
    }

    mutating private func shiftChildren(_ id: LayoutID, by offset: CGFloat) {
        guard offset != 0 else { return }
        var data: LineData = lineData(id)
        data.paint.generation += 1
        setKind(.line(data), at: id)
        let children: [LayoutID] = childrenIDs(of: id)
        let shifted: [CGFloat] = children.map({ x($0) + offset })

        for (child, x) in zip(children, shifted) {
            setField(.x, x, for: child)
        }
    }

    private func inlineWidth(_ id: LayoutID, index: Int, child: LayoutID) -> CGFloat {
        let widths: [CGFloat] = lineData(id).content.inlineWidths
        if index < widths.count {
            return widths[index]
        }
        return width(child)
    }

    private func contentWidth(_ id: LayoutID) -> CGFloat {
        let inline: [LayoutID] = childrenIDs(of: id).filter({ isText($0) || isEmbed($0) })
        guard let last: LayoutID = inline.last else { return 0 }
        let trailing: CGFloat = inlineWidth(id, index: inline.count - 1, child: last)
        return x(last) + trailing - x(id)
    }

    func lineCanCachePaint(_ id: LayoutID) -> Bool {
        return !lineData(id).content.hasEmbed
    }

    private func boxRevision(_ id: LayoutID) -> UInt64? {
        guard isBlock(id), isUsed(.inlineContent, at: id),
            !isDirty(.inlineContent, at: id)
        else { return nil }
        return inlineContent(id)
    }

    mutating private func layoutLineBoxes(_ id: LayoutID) {
        let data: LineData = lineData(id)
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
        var updated: LineData = data
        updated.content.boxes = boxes
        updated.content.inlineWidths = boxes.map({ $0.geometry.width })
        if let block: LayoutID = parentID(of: id), let revision: UInt64 = boxRevision(block) {
            updated.paint.boxRevision = revision
        }
        updated.paint.generation += 1
        updated.placement.childOriginY = y(id)
        updated.placement.inlineYOffset = 0
        setKind(.line(updated), at: id)
        setField(.height, maxAscent + maxDescent, for: id)
    }

    /// Boxes are only current when they still describe the live text
    /// children. Incremental text edits can replace a child without forcing a
    /// fresh line placement, in which case callers must fall back to nodes.
    func currentInlineBoxes(_ id: LayoutID) -> [InlineBox]? {
        let data: LineData = lineData(id)
        guard !data.content.hasEmbed, !data.content.boxes.isEmpty else { return nil }
        let block: LayoutID? = parentID(of: id)
        guard let block, let revision: UInt64 = boxRevision(block),
            data.paint.boxRevision == revision
        else { return nil }
        let children: [LayoutID] = childrenIDs(of: id).filter({ isText($0) })
        if children.isEmpty { return data.content.boxes }
        guard children.count == data.content.boxes.count else { return nil }
        for (box, child) in zip(data.content.boxes, children) {
            let text: TextData = textData(child)
            guard box.dom == domID(of: child),
                box.fragment == text.fragment,
                box.geometry.x == x(child),
                box.geometry.y + y(id) == textAbsoluteY(child),
                box.geometry.width == textTextWidth(child),
                inlineText(box) == textString(child)
            else { return nil }
        }
        return data.content.boxes
    }
}
