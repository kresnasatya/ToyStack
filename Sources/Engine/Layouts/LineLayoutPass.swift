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
            return
        }

        guard needsPlacement else {
            profiler.count("layout.line.place.skipped")
            return
        }

        for child in children { layout(child) }

        profiler.count("layout.line.place.placed")
        profiler.measure("layout.line.place", {
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
            for child in inlineChildren {
                if let previousFont, isEmbed(child) {
                    nextX += previousFont.spaceWidth
                }
                let childY: CGFloat = inputs.tag(domID(of: child)) == "sup"
                    ? baseline - maxAscent
                    : baseline - ascent(child)
                setPosition(x: nextX, y: childY, for: child)
                nextX += width(child)
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
        })
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

    private func contentWidth(_ id: LayoutID) -> CGFloat {
        guard let last: LayoutID = childrenIDs(of: id).last else { return 0 }
        let trailing: CGFloat = isText(last) ? textTextWidth(last) : width(last)
        return x(last) + trailing - x(id)
    }

    func lineCanCachePaint(_ id: LayoutID) -> Bool {
        return !lineData(id).content.hasEmbed
    }
}
