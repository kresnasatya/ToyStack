import CoreGraphics

// MARK: - TextLayoutPass

extension LayoutTree {
    mutating func makeText(
        _ text: TextData,
        dom: NodeID,
        parent: LayoutID?,
        previous: LayoutID?
    ) -> LayoutID {
        let kind: LayoutKind = .text(text)
        let id: LayoutID = append(kind: kind, dom: dom, parent: parent, previous: previous)
        setPrimary(id, for: dom)

        setChildrenClean([], of: id)
        setFontClean(inlineDefaultFont, for: id)
        setFieldClean(.ascent, inlineDefaultFont.ascent, for: id)
        setFieldClean(.descent, inlineDefaultFont.descent, for: id)
        for field in [
            LayoutField.zoom, .width, .height, .font, .x, .y,
        ] {
            markUsed(field, at: id)
        }
        markAncestorsDirty(from: id)
        markField(.font, at: id)
        return id
    }

    func textLayoutNeeded(_ id: LayoutID) -> Bool {
        if hasDirtyDescendants(at: id) {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: LayoutFieldStore = node(id).state.fields
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
                var data: TextData = textData(id)
                let resolvedFont: BrowserFont
                if let override = data.fontOverride {
                    resolvedFont = override
                } else {
                    resolvedFont = fontFor(domID(of: id), zoom: zoom(id))
                }
                setFont(resolvedFont, for: id)
                data = textData(id)
            }

            if fontChanged || isDirty(.width, at: id) || isDirty(.height, at: id)
                || isDirty(.ascent, at: id) || isDirty(.descent, at: id)
            {
                let measuredFont: BrowserFont = font(id)
                let data: TextData = textData(id)
                let measured: CGFloat = measuredFont.measure(data.display ?? data.word)
                var updated: TextData = data
                updated.metrics.width = measured
                setKind(.text(updated), at: id)
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
        let inlineOffset: CGFloat = parentID(of: id).map({ lineData($0).placement.inlineYOffset }) ?? 0
        return y(id) + inlineOffset
    }

    func textSelfRect(_ id: LayoutID) -> Rect {
        let top: CGFloat = textAbsoluteY(id)
        let x: CGFloat = x(id)
        return Rect(left: x, top: top, right: x + width(id), bottom: top + height(id))
    }

    func textTextWidth(_ id: LayoutID) -> CGFloat {
        return textData(id).metrics.width
    }

    mutating func attachText(_ id: LayoutID, to line: LayoutID, previous: LayoutID?) {
        setPrevious(previous, of: id)
    }
}
