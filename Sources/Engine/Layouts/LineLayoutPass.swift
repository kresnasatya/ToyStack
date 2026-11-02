import CoreGraphics

// MARK: - LineLayoutPass

extension LayoutTree {
    func makeLine(
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
        let ref: LayoutRef = LayoutRef(id: id, tree: self)
        ref.childrenField.setClean([])
        ref.childrenField.setDependencies([])
        ref.ascentField.setClean(0)
        ref.descentField.setClean(0)
        ref.markAncestorsDirty()
        let parentRef: LayoutRef = LayoutRef(id: parent, tree: self)
        ref.zoomField.setDependencies([parentRef.zoomField])
        ref.widthField.setDependencies([parentRef.widthField])
        ref.xField.setDependencies([parentRef.xField])
        var yInputs: [any InvalidatableField] = [parentRef.yField]
        if let previous {
            let previousRef: LayoutRef = LayoutRef(id: previous, tree: self)
            yInputs.append(previousRef.yField)
            yInputs.append(previousRef.heightField)
        }
        ref.yField.setDependencies(yInputs)
        ref.heightField.setDependencies([ref.ascentField, ref.descentField])
        return id
    }

    func lineLayoutNeeded(_ ref: LayoutRef) -> Bool {
        if ref.hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: LayoutFieldStore = node(ref.id).state.fields
        return state.isDirty(.zoom) || state.isDirty(.x) || state.isDirty(.y)
            || state.isDirty(.width) || state.isDirty(.height)
            || state.isDirty(.ascent) || state.isDirty(.descent)
    }

    func layoutLine(_ ref: LayoutRef) {
        guard lineLayoutNeeded(ref) else { return }
        defer { ref.hasDirtyDescendants = false }
        let xWasDirty: Bool = ref.tree.isDirty(.x, at: ref.id)
        let yWasDirty: Bool = ref.tree.isDirty(.y, at: ref.id)
        let zoomWasDirty: Bool = ref.tree.isDirty(.zoom, at: ref.id)
        let children: [LayoutRef] = ref.children
        var data: LineData = ref.lineData
        let childCountChanged: Bool = children.count != data.placement.declaredInlineChildCount
        var childWidthChanged: Bool = false
        for child in children where child.tree.isDirty(.width, at: child.id) {
            childWidthChanged = true
            break
        }
        if children.count != data.paint.paintedChildCount {
            data.paint.generation += 1
            data.paint.paintedChildCount = children.count
            ref.lineData = data
        }
        let parent: LayoutRef = ref.parent!
        ref.zoomField.copy(from: parent.zoomField)
        ref.widthField.copy(from: parent.widthField)
        ref.xField.copy(from: parent.xField)
        if let previous: LayoutRef = ref.previous {
            ref.y = previous.yField.read(notify: ref.yField)
                + previous.heightField.read(notify: ref.yField)
        } else {
            ref.yField.copy(from: parent.yField)
        }

        for child in children { child.layout() }

        if children.count != data.placement.declaredInlineChildCount {
            setInlineInputs(ref, children: children)
            var updated: LineData = ref.lineData
            updated.placement.declaredInlineChildCount = children.count
            ref.lineData = updated
        }

        let widthMovesChildren: Bool = ref.lineData.content.centered
            || ref.node.style.computed.text.direction == .rtl
        let needsPlacement: Bool = xWasDirty || yWasDirty || childCountChanged
            || childWidthChanged
            || ref.tree.isDirty(.ascent, at: ref.id)
            || ref.tree.isDirty(.descent, at: ref.id)
            || ref.tree.isDirty(.height, at: ref.id)
            || ref.tree.isDirty(.children, at: ref.id)
            || widthMovesChildren

        let textOnly: Bool = children.allSatisfy({ $0.isText })
        let verticalOnly: Bool = yWasDirty && !xWasDirty && !zoomWasDirty
            && !childCountChanged && !childWidthChanged && !widthMovesChildren
            && !ref.tree.isDirty(.ascent, at: ref.id)
            && !ref.tree.isDirty(.descent, at: ref.id)
            && !ref.tree.isDirty(.height, at: ref.id)
            && !ref.tree.isDirty(.children, at: ref.id)
            && textOnly && ref.lineData.placement.childOriginY != nil

        if verticalOnly, let childOriginY: CGFloat = ref.lineData.placement.childOriginY {
            profiler.count("layout.line.place.verticalOnly")
            profiler.measure("layout.line.place.vertical", {
                var updated: LineData = ref.lineData
                updated.placement.inlineYOffset = ref.y - childOriginY
                ref.lineData = updated
            })
            return
        }

        guard needsPlacement else {
            profiler.count("layout.line.place.skipped")
            return
        }

        profiler.count("layout.line.place.placed")
        profiler.measure("layout.line.place", {
            guard !children.isEmpty else {
                ref.ascentField.set(0)
                ref.descentField.set(0)
                ref.heightField.set(0)
                return
            }

            let inlineChildren: [LayoutRef] = children.filter({ $0.isText || $0.isEmbed })
            guard !inlineChildren.isEmpty else {
                ref.heightField.set(0)
                return
            }

            let maxAscent: CGFloat = inlineChildren.map {
                $0.ascentField.read(notify: ref.ascentField)
            }.max() ?? 0
            ref.ascentField.set(maxAscent)
            let maxDescent: CGFloat = inlineChildren.map {
                $0.descentField.read(notify: ref.descentField)
            }.max() ?? 0
            ref.descentField.set(maxDescent)

            var nextX: CGFloat = ref.x
            var previousFont: BrowserFont? = nil
            for child in inlineChildren {
                if let previousFont, child.isEmbed {
                    nextX += previousFont.spaceWidth
                }
                child.xField.set(nextX)
                nextX += child.widthField.get()
                previousFont = child.fontField.get()
            }

            let lineY: CGFloat = ref.y
            let baseline: CGFloat = lineY + ref.ascent
            for child in inlineChildren {
                if let el = child.node.element, el.tag == "sup" {
                    child.yField.set(baseline - maxAscent)
                } else {
                    child.yField.set(baseline - child.ascentField.get())
                }
            }

            for child in children where !child.children.isEmpty {
                child.layout()
            }

            if ref.node.style.computed.text.direction == .rtl {
                let usedWidth: CGFloat = contentWidth(ref)
                shiftChildren(ref, by: ref.width - usedWidth)
            }

            if ref.lineData.content.centered {
                let usedWidth: CGFloat = contentWidth(ref)
                shiftChildren(ref, by: (ref.width - usedWidth) / 2)
            }

            ref.height = ref.ascentField.read(notify: ref.heightField)
                + ref.descentField.read(notify: ref.heightField)
            var updated: LineData = ref.lineData
            updated.placement.childOriginY = ref.y
            updated.placement.inlineYOffset = 0
            ref.lineData = updated
        })
    }

    private func setInlineInputs(_ ref: LayoutRef, children: [LayoutRef]) {
        var ascents: [any InvalidatableField] = []
        var descents: [any InvalidatableField] = []
        for child in children where child.isText || child.isEmbed {
            ascents.append(child.ascentField)
            descents.append(child.descentField)
        }
        ref.ascentField.setDependencies(ascents)
        ref.descentField.setDependencies(descents)
    }

    private func shiftChildren(_ ref: LayoutRef, by offset: CGFloat) {
        guard offset != 0 else { return }
        var data: LineData = ref.lineData
        data.paint.generation += 1
        ref.lineData = data
        let children: [LayoutRef] = ref.children
        let shifted: [CGFloat] = children.map { $0.x + offset }

        for (child, x) in zip(children, shifted) {
            child.x = x
        }
    }

    private func contentWidth(_ ref: LayoutRef) -> CGFloat {
        guard let last: LayoutRef = ref.children.last else { return 0 }
        let trailing: CGFloat = last.isText ? textTextWidth(last) : last.width
        return last.x + trailing - ref.x
    }

    func lineCanCachePaint(_ ref: LayoutRef) -> Bool {
        return !ref.lineData.content.hasEmbed
    }

    func paintLine(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        var outlineRect: Rect? = nil
        var focused: DOMRef? = nil
        for child in ref.children {
            guard let ancestor: DOMRef = focusVisibleInlineAncestor(child.node, line: ref) else { continue }
            focused = ancestor
            let childRect: Rect = child.selfRect()
            outlineRect = outlineRect?.union(childRect) ?? childRect
        }
        if let rect = outlineRect, let focused {
            if let outline: DisplayOp = DisplayOp.fromStyle(focused, rect: rect) {
                items.append(outline)
            } else {
                items.append(.outline(rect: rect, color: BrowserColor(cssName: focusRingColors(ref.node).outer), width: 4))
                items.append(.outline(rect: rect, color: BrowserColor(cssName: focusRingColors(ref.node).inner), width: 2))
            }
        }
    }

    private func focusVisibleInlineAncestor(_ start: DOMRef, line: LayoutRef) -> DOMRef? {
        var current: DOMRef? = start.parent
        while let ancestor = current, ancestor.id != line.domNode {
            if ancestor.isFocusVisible { return ancestor }
            current = ancestor.parent
        }
        return nil
    }

    func lineSelfRect(_ ref: LayoutRef) -> Rect {
        return ref.selfRect()
    }
}
