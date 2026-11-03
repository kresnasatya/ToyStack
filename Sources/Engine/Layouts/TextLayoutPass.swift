import CoreGraphics

// MARK: - TextLayoutPass

extension LayoutTree {
    func makeText(
        _ text: TextData,
        dom: NodeID,
        parent: LayoutID?,
        previous: LayoutID?
    ) -> LayoutID {
        let kind: LayoutKind = .text(text)
        let id: LayoutID = append(kind: kind, dom: dom, parent: parent, previous: previous)
        setPrimary(id, for: dom)
        let ref: LayoutRef = LayoutRef(id: id, tree: self)

        setChildrenClean([], of: id)
        setFontClean(inlineDefaultFont, for: id)
        setFieldClean(.ascent, inlineDefaultFont.ascent, for: id)
        setFieldClean(.descent, inlineDefaultFont.descent, for: id)
        for field in [
            LayoutField.zoom, .width, .height, .font, .x, .y,
        ] {
            markUsed(field, at: id)
        }
        ref.markAncestorsDirty()
        markField(.font, at: id)
        addDependencyEdges(for: id)
        return id
    }

    func textLayoutNeeded(_ ref: LayoutRef) -> Bool {
        if ref.hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: LayoutFieldStore = node(ref.id).state.fields
        return state.isDirty(.zoom) || state.isDirty(.width) || state.isDirty(.height)
            || state.isDirty(.font) || state.isDirty(.ascent) || state.isDirty(.descent)
    }

    func layoutText(_ ref: LayoutRef) {
        guard textLayoutNeeded(ref) else { return }
        defer { ref.hasDirtyDescendants = false }
        profiler.measure("layout.text", {
            if ref.tree.isDirty(.zoom, at: ref.id) {
                ref.zoom = ref.resolvedZoom()
            }

            let fontChanged: Bool = ref.tree.isDirty(.font, at: ref.id)
            if fontChanged {
                var data: TextData = ref.textData
                let resolvedFont: BrowserFont
                if let override = data.fontOverride {
                    resolvedFont = override
                } else {
                    resolvedFont = fontForElement(ref.node, zoom: ref.zoom)
                }
                ref.font = resolvedFont
                data = ref.textData
            }

            if fontChanged || ref.tree.isDirty(.width, at: ref.id) {
                let measuredFont: BrowserFont = ref.font
                let measured: CGFloat = measuredFont.measure(ref.textData.display ?? ref.textData.word)
                var data: TextData = ref.textData
                data.metrics.width = measured
                ref.textData = data
                ref.width = measured + measuredFont.spaceWidth
            }

            if fontChanged || ref.tree.isDirty(.height, at: ref.id) {
                ref.height = ref.font.linespace
            }
            if fontChanged || ref.tree.isDirty(.ascent, at: ref.id) {
                ref.ascent = ref.font.ascent
            }
            if fontChanged || ref.tree.isDirty(.descent, at: ref.id) {
                ref.descent = ref.font.descent
            }
        })
    }

    func textAbsoluteY(_ ref: LayoutRef) -> CGFloat {
        return ref.y + (ref.parent?.lineData.placement.inlineYOffset ?? 0)
    }

    func textSelfRect(_ ref: LayoutRef) -> Rect {
        let top: CGFloat = textAbsoluteY(ref)
        return Rect(left: ref.x, top: top, right: ref.x + ref.width, bottom: top + ref.height)
    }

    func paintText(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        let data: TextData = ref.textData
        let color: BrowserColor = ref.node.inheritedStyleOwner.style.computed.text.color
        let top: CGFloat = textAbsoluteY(ref)
        items.append(
            .text(
                text: data.display ?? data.word,
                font: ref.font,
                color: color,
                rect: Rect(
                    left: ref.x,
                    top: top,
                    right: ref.x + data.metrics.width,
                    bottom: top + ref.font.linespace
                )
            )
        )
    }

    func textTextWidth(_ ref: LayoutRef) -> CGFloat {
        return ref.textData.metrics.width
    }

    func attachText(_ ref: LayoutRef, to line: LayoutID, previous: LayoutID?) {
        setPrevious(previous, of: ref.id)
    }
}
