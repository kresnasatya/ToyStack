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

        ref.childrenField.setClean([])
        ref.childrenField.setDependencies([])
        ref.fontField.setClean(inlineDefaultFont)
        ref.ascentField.setClean(inlineDefaultFont.ascent)
        ref.descentField.setClean(inlineDefaultFont.descent)
        ref.markAncestorsDirty()

        var zoomInputs: [any InvalidatableField] = [ref.node.style.field(.zoom)]
        if let parent {
            zoomInputs.append(LayoutRef(id: parent, tree: self).zoomField)
        }
        ref.zoomField.setDependencies(zoomInputs)

        ref.fontField.setDependencies([ref.zoomField] + fontInputs(for: ref.node))
        ref.fontField.mark()
        ref.widthField.setDependencies([ref.fontField])
        ref.heightField.setDependencies([ref.fontField])
        ref.ascentField.setDependencies([ref.fontField])
        ref.descentField.setDependencies([ref.fontField])
        // Position is assigned by the containing line; there are no inputs.
        ref.xField.setDependencies([])
        ref.yField.setDependencies([])
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
                ref.zoomField.set(ref.resolvedZoom())
            }

            let fontChanged: Bool = ref.tree.isDirty(.font, at: ref.id)
            if fontChanged {
                var data: TextData = ref.textData
                let resolvedFont: BrowserFont
                if let override = data.fontOverride {
                    resolvedFont = override
                } else {
                    resolvedFont = fontForElement(
                        ref.node,
                        zoom: ref.zoomField.read(notify: ref.fontField),
                        notify: ref.fontField
                    )
                }
                ref.font = resolvedFont
                data = ref.textData
            }

            if fontChanged || ref.tree.isDirty(.width, at: ref.id) {
                let measuredFont: BrowserFont = ref.fontField.read(notify: ref.widthField)
                let measured: CGFloat = measuredFont.measure(ref.textData.display ?? ref.textData.word)
                var data: TextData = ref.textData
                data.metrics.width = measured
                ref.textData = data
                ref.width = measured + measuredFont.spaceWidth
            }

            if fontChanged || ref.tree.isDirty(.height, at: ref.id) {
                ref.height = ref.fontField.read(notify: ref.heightField).linespace
            }
            if fontChanged || ref.tree.isDirty(.ascent, at: ref.id) {
                ref.ascent = ref.fontField.read(notify: ref.ascentField).ascent
            }
            if fontChanged || ref.tree.isDirty(.descent, at: ref.id) {
                ref.descent = ref.fontField.read(notify: ref.descentField).descent
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
        let lineRef: LayoutRef = LayoutRef(id: line, tree: self)
        ref.zoomField.setDependencies([ref.node.style.field(.zoom), lineRef.zoomField])
    }
}
