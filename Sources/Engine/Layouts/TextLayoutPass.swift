import CoreGraphics

// MARK: - TextLayoutPass

extension LayoutTree {
    mutating func makeText(
        _ text: TextData,
        dom: NodeID,
        parent: LayoutID?,
        previous: LayoutID?
    ) -> LayoutID {
        var fields: LayoutFieldStore = LayoutFieldStore()
        fields.inlineText.font = inlineDefaultFont
        fields.inlineText.ascent = inlineDefaultFont.ascent
        fields.inlineText.descent = inlineDefaultFont.descent
        let used: [LayoutField] = [
            .children, .font, .ascent, .descent,
            .zoom, .width, .height, .x, .y,
        ]
        fields.state.usedBits = used.reduce(0) { mask, field in mask | field.mask }
        fields.state.dirtyBits =
            LayoutField.allMask
            & ~(LayoutField.ascent.mask | LayoutField.descent.mask | LayoutField.children.mask)

        let links: LayoutLinks = LayoutLinks(
            parent: parent,
            previous: previous,
            children: [],
            versions: LinkVersions(children: 1, previous: 0)
        )
        let state: LayoutState = LayoutState(
            fields: fields,
            hasDirtyDescendants: false,
            isRemoved: false
        )
        let id: LayoutID = append(
            LayoutNodeSeed(kind: .text(text), dom: dom, links: links, state: state)
        )
        setPrimary(id, for: dom)
        for field in used {
            let dependent: FieldKey = .layout(id, field)
            for input in LayoutInputTable.inputs(for: id, field: field, in: self) {
                dependencies.add(dependent, for: input)
            }
        }
        markAncestorsDirty(from: id)
        return id
    }

    func textLayoutNeeded(_ id: LayoutID) -> Bool {
        if hasDirtyDescendants(at: id) {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: FieldState = self[node: id].state.fields.state
        return state.isDirty(.zoom) || state.isDirty(.width) || state.isDirty(.height)
            || state.isDirty(.font) || state.isDirty(.ascent) || state.isDirty(.descent)
    }

    mutating func layoutText(_ id: LayoutID) {
        guard textLayoutNeeded(id) else { return }
        defer { setDirtyDescendants(false, at: id) }
        profiler.measure("layout.text", {
            if isDirty(.zoom, at: id) {
                setField(.zoom, resolvedZoom(id), for: id)
            }

            let fontChanged: Bool = isDirty(.font, at: id)
            if fontChanged {
                let resolvedFont: BrowserFont
                if let override = self[text: id].payload.fontOverride {
                    resolvedFont = override
                } else {
                    resolvedFont = fontFor(domID(of: id), zoom: zoom(id))
                }
                setFont(resolvedFont, for: id)
            }

            if fontChanged || isDirty(.width, at: id) || isDirty(.height, at: id)
                || isDirty(.ascent, at: id) || isDirty(.descent, at: id)
            {
                let measuredFont: BrowserFont = font(id)
                let measured: CGFloat
                if self[text: id].metrics.measured {
                    profiler.count("text.measureReused")
                    measured = self[text: id].metrics.width
                } else {
                    measured = measuredFont.measure(textString(id))
                    self[text: id].metrics.width = measured
                    self[text: id].metrics.measured = true
                }
                setTextMetrics(
                    id,
                    width: measured + measuredFont.spaceWidth,
                    vertical: (
                        height: measuredFont.linespace,
                        ascent: measuredFont.ascent,
                        descent: measuredFont.descent
                    )
                )
            }
        })
    }

    func textAbsoluteY(_ id: LayoutID) -> CGFloat {
        let inlineOffset: CGFloat = parentID(of: id).map({ self[line: $0].placement.inlineYOffset }) ?? 0
        return y(id) + inlineOffset
    }

    func textSelfRect(_ id: LayoutID) -> Rect {
        let top: CGFloat = textAbsoluteY(id)
        let x: CGFloat = x(id)
        return Rect(left: x, top: top, right: x + textTextWidth(id), bottom: top + height(id))
    }

    func textTextWidth(_ id: LayoutID) -> CGFloat {
        guard let line: LayoutID = parentID(of: id) else {
            return self[text: id].metrics.width
        }
        let inline: [LayoutID] = childrenIDs(of: line).filter({ isText($0) || isEmbed($0) })
        guard let index: Int = inline.firstIndex(of: id) else {
            return self[text: id].metrics.width
        }
        let widths: [CGFloat] = self[line: line].content.inlineWidths
        if index < widths.count {
            return widths[index]
        }
        return self[text: id].metrics.width
    }
}
