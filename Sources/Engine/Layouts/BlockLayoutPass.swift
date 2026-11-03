import CoreGraphics

// MARK: - BlockLayoutPass

extension LayoutTree {
    static let hiddenElements: Set<String> = ["head", "title", "script", "style"]
    static let liIndent: CGFloat = 20.0
    static let bulletSize: CGFloat = 8.0

    // MARK: - Construction

    func makeBlock(
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
        let ref: LayoutRef = LayoutRef(id: id, tree: self)
        initializeBlock(ref, extraNodes: [], parent: parent, previous: previous)
        return id
    }

    func makeAnonymousBlock(
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
        let ref: LayoutRef = LayoutRef(id: id, tree: self)
        initializeBlock(ref, extraNodes: extraNodes, parent: parent, previous: previous)
        return id
    }

    private func initializeBlock(
        _ ref: LayoutRef,
        extraNodes: [NodeID],
        parent: LayoutID,
        previous: LayoutID?
    ) {
        var data: BlockData = ref.blockData
        data.content.extraNodes = extraNodes
        ref.blockData = data
        ref.previousField.setClean(previous)
        ref.previousField.setDependencies([])
        ref.markAncestorsDirty()
        freezeBlockGeometry(ref, parent: parent, previous: previous)
    }

    private func freezeBlockGeometry(
        _ ref: LayoutRef,
        parent: LayoutID,
        previous: LayoutID?
    ) {
        let parentRef: LayoutRef = LayoutRef(id: parent, tree: self)
        ref.zoomField.setDependencies([parentRef.zoomField, ref.node.style.field(.zoom)])
        ref.xField.setDependencies([
            parentRef.xField,
            ref.zoomField,
            ref.node.style.field(.paddingLeft),
            ref.node.style.field(.position),
            ref.node.style.field(.left),
        ])
        var yInputs: [any InvalidatableField] = [
            parentRef.yField,
            ref.previousField,
            ref.zoomField,
            ref.node.style.field(.paddingTop),
            ref.node.style.field(.top),
            ref.node.style.field(.marginTop),
        ]
        if let previous {
            let previousRef: LayoutRef = LayoutRef(id: previous, tree: self)
            yInputs.append(previousRef.yField)
            yInputs.append(previousRef.heightField)
            yInputs.append(previousRef.node.style.field(.marginBottom))
            yInputs.append(previousRef.node.style.field(.paddingBottom))
        }
        ref.yField.setDependencies(yInputs)
        ref.widthField.setDependencies([
            parentRef.widthField,
            ref.zoomField,
            ref.node.style.field(.paddingLeft),
            ref.node.style.field(.paddingRight),
            ref.node.style.field(.width),
        ])
        let contentInputs: [any InvalidatableField] = inlineContentInputs(ref)
        ref.inlineContentField.setDependencies(contentInputs)
        ref.childrenField.setDependencies(contentInputs + [ref.inlineContentField])
    }

    func blockExtraNodes(_ ref: LayoutRef) -> [DOMRef] {
        return ref.blockData.content.extraNodes.map({ DOMRef(id: $0, dom: dom) })
    }

    func inlineContentInputs(_ ref: LayoutRef) -> [any InvalidatableField] {
        let extraNodes: [DOMRef] = blockExtraNodes(ref)
        var inputs: [any InvalidatableField] = [
            ref.zoomField,
            ref.node.style.field(.display),
            ref.node.style.field(.position),
            ref.node.style.field(.direction),
        ]
        if extraNodes.isEmpty {
            for child in ref.node.children {
                inputs.append(child.style.field(.display))
                inputs.append(child.style.field(.position))
            }
        }
        for leaf in inlineLeaves(ref) {
            let owner: DOMRef = leaf.inheritedStyleOwner
            inputs.append(owner.style.field(.whiteSpace))
            inputs.append(contentsOf: fontInputs(for: leaf))
            if let el = leaf.element {
                inputs.append(el.style.field(.aspectRatio))
                inputs.append(el.style.field(.maxWidth))
            }
        }
        return inputs
    }

    // Only leaves this block lays out inline. Nested blocks own their own inputs.
    private func inlineLeaves(_ ref: LayoutRef) -> [DOMRef] {
        var leaves: [DOMRef] = []
        let extraNodes: [DOMRef] = blockExtraNodes(ref)
        if !extraNodes.isEmpty {
            for node in extraNodes { collectLeaves(node, into: &leaves) }
            return leaves
        }
        let hasBlockChild: Bool = ref.node.children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if !hasBlockChild {
            collectLeaves(ref.node, into: &leaves)
            return leaves
        }
        for child in ref.node.children where child.style.computed.layout.display != .block {
            collectLeaves(child, into: &leaves)
        }
        return leaves
    }

    // MARK: - Line plan

    private func inlineTextLinePlan(_ ref: LayoutRef) -> [[Int]]? {
        let items: [InlineItem] = ref.blockData.content.inlineItems
        var plan: [[Int]] = []
        var current: [Int] = []
        var cursorX: CGFloat = 0
        let availableWidth: CGFloat = ref.width
        var updated: [InlineItem] = items

        for index in updated.indices {
            switch updated[index] {
            case .lineBreak:
                plan.append(current)
                current = []
                cursorX = 0
            case .embed:
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
                }
                let width: CGFloat = wordWidth + font.spaceWidth
                if cursorX + width > availableWidth && text.run.whiteSpace.wraps {
                    plan.append(current)
                    current = []
                    cursorX = 0
                }
                current.append(index)
                cursorX += width
            }
        }

        var data: BlockData = ref.blockData
        data.content.inlineItems = updated
        ref.blockData = data
        plan.append(current)
        return plan
    }

    private func setHeightInputs(_ ref: LayoutRef) {
        let children: [LayoutRef] = ref.children
        let declared: [LayoutID] = ref.blockData.changes.declaredHeightChildren
        let unchanged: Bool = children.map({ $0.id }) == declared
        if unchanged { return }
        var data: BlockData = ref.blockData
        data.changes.declaredHeightChildren = children.map({ $0.id })
        ref.blockData = data
        ref.heightField.setDependencies(blockHeightInputs(ref))
    }

    func blockHeightInputs(_ ref: LayoutRef) -> [any InvalidatableField] {
        var inputs: [any InvalidatableField] = [
            ref.childrenField,
            ref.zoomField,
            ref.node.style.field(.height),
            ref.node.style.field(.overflow),
        ]
        for child in ref.children {
            inputs.append(child.heightField)
            inputs.append(child.node.style.field(.position))
            inputs.append(child.node.style.field(.marginTop))
            inputs.append(child.node.style.field(.marginBottom))
            if child.isBlock {
                inputs.append(child.zoomField)
                inputs.append(child.node.style.field(.paddingTop))
                inputs.append(child.node.style.field(.paddingBottom))
            }
        }
        return inputs
    }

    func blockMarkChildrenDirty(_ ref: LayoutRef) {
        var data: BlockData = ref.blockData
        data.changes.childChanges.removeAll()
        ref.blockData = data
        ref.inlineContentField.mark()
        ref.childrenField.mark()
    }

    func blockNoteAppendedChildren(_ ref: LayoutRef, _ nodes: [DOMRef]) {
        var data: BlockData = ref.blockData
        data.changes.childChanges.append(.append(nodes))
        ref.blockData = data
        ref.markAncestorsDirty()
    }

    func blockNoteInsertedChildren(_ ref: LayoutRef, _ nodes: [DOMRef], before reference: DOMRef) {
        var data: BlockData = ref.blockData
        data.changes.childChanges.append(.insert(nodes, before: reference))
        ref.blockData = data
        ref.markAncestorsDirty()
    }

    func setBlockPrevious(_ ref: LayoutRef, _ newValue: LayoutID?) {
        ref.previousField.set(newValue)
        guard let newValue else { return }
        let newRef: LayoutRef = LayoutRef(id: newValue, tree: self)
        ref.yField.setDependencies([
            newRef.yField,
            newRef.heightField,
            newRef.node.style.field(.marginBottom),
            newRef.node.style.field(.paddingBottom),
        ])
    }

    func blockPrevious(_ ref: LayoutRef) -> LayoutID? {
        return ref.previousField.get()
    }

    func blockLayoutNeeded(_ ref: LayoutRef) -> Bool {
        if ref.hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let state: LayoutFieldStore = node(ref.id).state.fields
        if state.isDirty(.zoom) || state.isDirty(.x) || state.isDirty(.y)
            || state.isDirty(.width) || state.isDirty(.height)
        {
            return true
        }
        return state.isDirty(.inlineContent)
            || state.isDirty(.children)
            || !ref.blockData.changes.childChanges.isEmpty
    }

    func layoutBlock(_ ref: LayoutRef) {
        guard blockLayoutNeeded(ref) else {
            profiler.count("layout.skipped")
            return
        }
        defer { ref.hasDirtyDescendants = false }
        profiler.count("layout.visited")
        // A display change moves children between the block and inline paths, so
        // the leaves that inline layout will read were not known when the block
        // was built. Re-declare them before this pass reads them.
        if ref.tree.isDirty(.inlineContent, at: ref.id)
            || ref.tree.isDirty(.children, at: ref.id)
            || !ref.blockData.changes.childChanges.isEmpty
        {
            let contentInputs: [any InvalidatableField] = inlineContentInputs(ref)
            ref.inlineContentField.setDependencies(contentInputs)
            ref.childrenField.setDependencies(contentInputs + [ref.inlineContentField])
        }

        let style: BlockStyle = blockStyle(ref)
        profiler.measure("layout.visit") {
            profiler.count("layout.rebuilt")
            ref.zoom = ref.resolvedZoom()
            let isAbsolute: Bool = style.position == .absolute

            let parentX: CGFloat = ref.parent!.xField.read(notify: ref.xField)
            let padLeft: CGFloat = blockExtraNodes(ref).isEmpty ? style.box.padding.left * ref.zoom : 0
            if isAbsolute, let l = style.flags.left {
                let absoluteXZoom: CGFloat = ref.zoomField.read(notify: ref.xField)
                ref.xField.set(l * absoluteXZoom + padLeft)
            } else {
                ref.xField.set(parentX + padLeft)
            }

            let parentWidth: CGFloat = ref.parent!.widthField.read(notify: ref.widthField)
            let zoom: CGFloat = ref.zoomField.read(notify: ref.widthField)
            let padHorizontal: CGFloat = blockExtraNodes(ref).isEmpty
                ? (style.box.padding.left + style.box.padding.right) * zoom
                : 0
            if let w = style.box.width {
                ref.widthField.set(w * zoom)
            } else {
                ref.widthField.set(max(0, parentWidth - padHorizontal))
            }

            if let el = ref.node.element, el.tag == "li" {
                ref.x += LayoutTree.liIndent
                ref.width -= LayoutTree.liIndent
            }

            if isAbsolute, let t = style.flags.top {
                let absoluteYZoom: CGFloat = ref.zoomField.read(notify: ref.yField)
                let padTop: CGFloat = blockExtraNodes(ref).isEmpty ? style.box.padding.left * zoom : 0
                ref.yField.set(t * absoluteYZoom + padTop)
            } else {
                let ownTop: CGFloat = style.box.margin.top * zoom
                let padTop: CGFloat = style.box.padding.top * zoom
                if let previous: LayoutID = blockPrevious(ref) {
                    let prev: LayoutRef = LayoutRef(id: previous, tree: self)
                    let prevY: CGFloat = prev.yField.read(notify: ref.yField)
                    let prevHeight: CGFloat = prev.heightField.read(notify: ref.yField)
                    let prevPadBottom: CGFloat = prev.isBlock
                        ? prev.padding(.paddingBottom, notify: ref.yField)
                        : 0
                    ref.yField.set(
                        prevY + prevHeight + prevPadBottom
                            + (prev.isBlock ? prev.blockStyle().box.margin.bottom : 0) * zoom
                            + ownTop + padTop
                    )
                } else {
                    ref.yField.copy(from: ref.parent!.yField)
                    ref.yField.set(ref.yField.get() + ownTop + padTop)
                }
            }

            if let el = ref.node.element, el.attributes["id"] == "toc" {
                ref.y += VSTEP
            }

            let mode: String = profiler.measure("layout.mode", { layoutMode(ref) })
            if mode == "block" {
                profiler.count("layout.mode.block")
                if ref.tree.isDirty(.children, at: ref.id) {
                    ref.children = rebuildBlockChildren(ref).map({ LayoutRef(id: $0, tree: self) })
                } else if !ref.blockData.changes.childChanges.isEmpty {
                    let changes: [BlockChildChange] = ref.blockData.changes.childChanges
                    var data: BlockData = ref.blockData
                    data.changes.childChanges.removeAll()
                    ref.blockData = data
                    if let changed: [LayoutID] = applyBlockChanges(ref, changes) {
                        countChildChanges(changes)
                        ref.children = changed.map({ LayoutRef(id: $0, tree: self) })
                    } else {
                        ref.children = rebuildBlockChildren(ref).map({ LayoutRef(id: $0, tree: self) })
                    }
                }

                if ref.tree.isDirty(.inlineContent, at: ref.id) {
                    let revision: UInt64 = ref.tree.node(ref.id).state.fields.inlineText.inlineContent + 1
                    ref.inlineContentField.setClean(revision)
                    var data: BlockData = ref.blockData
                    data.content.inlineObjects.removeAll(keepingCapacity: true)
                    data.content.inlineLinePlan = nil
                    ref.blockData = data
                }
            } else {
                profiler.count("layout.mode.inline")
                let inlineContentChanged: Bool = ref.tree.isDirty(.inlineContent, at: ref.id)
                    || !ref.blockData.changes.childChanges.isEmpty
                var data: BlockData = ref.blockData
                data.changes.childChanges.removeAll()
                ref.blockData = data
                _ = ref.zoomField.read(notify: ref.childrenField)
                ref.node.style.field(.direction).touch(ref.childrenField)
                if inlineContentChanged {
                    profiler.measure("layout.inline.refresh", { refreshInlineItems(ref) })
                }
                let plan: [[Int]]? = inlineTextLinePlan(ref)
                let shouldPlace: Bool = inlineContentChanged
                    || plan == nil
                    || plan != ref.blockData.content.inlineLinePlan
                if shouldPlace {
                    profiler.measure("layout.inline.place", { placeInlineItems(ref) })
                } else {
                    ref.childrenField.set(ref.childrenField.peek() ?? [])
                }
                var updated: BlockData = ref.blockData
                updated.content.inlineLinePlan = plan
                ref.blockData = updated
            }
        }

        for child in ref.children { child.layout() }

        setHeightInputs(ref)
        let heightChildren: [LayoutID] = ref.childrenField.read(notify: ref.heightField)
        let sumHeight: Double = profiler.measure("layout.height", {
            heightChildren.reduce(0) { total, childID in
                let child: LayoutRef = LayoutRef(id: childID, tree: self)
                child.node.style.field(.position).touch(ref.heightField)
                let position: LayoutStyle.Position = child.node.style.computed.layout.position.kind
                if position == .absolute { return total }
                var h: CGFloat = child.heightField.read(notify: ref.heightField)
                if child.isBlock {
                    let childStyle: BlockStyle = child.blockStyle()
                    let childZoom: CGFloat = child.zoomField.read(notify: ref.heightField)
                    h += (childStyle.box.padding.top + childStyle.box.padding.bottom) * childZoom
                    h += (childStyle.box.margin.top + childStyle.box.margin.bottom) * childZoom
                }
                return total + h
            }
        })

        ref.node.style.field(.height).touch(ref.heightField)
        var scroll: BlockScroll = ref.blockData.scroll
        if let h: CGFloat = ref.node.style.computed.box.size.height {
            scroll.contentHeight = sumHeight
            let styleHeightZoom: CGFloat = ref.zoomField.read(notify: ref.heightField)
            ref.heightField.set(h * styleHeightZoom)
        } else {
            scroll.contentHeight = sumHeight
            ref.heightField.set(sumHeight)
        }

        if let el = ref.node.element, el.attributes["id"] == "toc" {
            ref.height += VSTEP
        }

        if style.flags.overflowScroll, let el = ref.node.element {
            let maxScroll: CGFloat = max(0, scroll.contentHeight - ref.height)
            scroll.offset = min(el.scrollOffsetY, maxScroll)
        }
        var data: BlockData = ref.blockData
        data.scroll = scroll
        ref.blockData = data
    }

    private func layoutMode(_ ref: LayoutRef) -> String {
        if !blockExtraNodes(ref).isEmpty { return "inline" }
        if ref.node.text != nil { return "inline" }
        let hasBlockChild: Bool = ref.node.children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if hasBlockChild { return "block" }
        if let el = ref.node.element {
            return (el.children.isEmpty && el.tag != "input" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas") ? "block" : "inline"
        }
        return "inline"
    }

    private func rebuildBlockChildren(_ ref: LayoutRef) -> [LayoutID] {
        profiler.count("layout.children.rebuilt")
        var data: BlockData = ref.blockData
        data.changes.childChanges.removeAll()
        ref.blockData = data
        var state: BlockChildBuild = BlockChildBuild()
        consumeBlockChildren(ref, ref.node.children, state: &state)
        finishBlockChildren(ref, &state)
        return state.built
    }

    private func appendBlockChildren(
        _ ref: LayoutRef,
        _ nodes: [DOMRef],
        to current: [LayoutID]
    ) -> [LayoutID]? {
        guard blockExtraNodes(ref).isEmpty,
            current.allSatisfy({ LayoutRef(id: $0, tree: self).isBlock })
        else {
            return nil
        }
        if let lastID: LayoutID = current.last {
            let last: LayoutRef = LayoutRef(id: lastID, tree: self)
            if blockExtraNodes(last).isEmpty, last.node.element?.tag == "h6" {
                return nil
            }
        }
        guard let first: DOMRef = firstVisibleChild(in: nodes) else {
            return nil
        }

        var state: BlockChildBuild = BlockChildBuild(
            built: current,
            previous: lastFlowChild(ref, in: current)
        )
        let startsInline: Bool = first.style.computed.layout.display != .block
        if startsInline, let lastID: LayoutID = state.built.last {
            let last: LayoutRef = LayoutRef(id: lastID, tree: self)
            let extras: [DOMRef] = blockExtraNodes(last)
            if !extras.isEmpty,
                extras.allSatisfy({ $0.style.computed.layout.display != .block })
            {
                state.built.removeLast()
                state.inlineRun = extras
                state.previous = last.previous?.id
            }
        }

        consumeBlockChildren(ref, nodes, state: &state)
        finishBlockChildren(ref, &state)
        return state.built
    }

    private func applyBlockChanges(
        _ ref: LayoutRef,
        _ changes: [BlockChildChange]
    ) -> [LayoutID]? {
        var current: [LayoutID] = ref.children.map({ $0.id })
        for change in changes {
            switch change {
            case .append(let nodes):
                guard let next: [LayoutID] = appendBlockChildren(ref, nodes, to: current) else {
                    return nil
                }
                current = next
            case .insert(let nodes, let reference):
                guard let next: [LayoutID] = insertBlockChildren(
                    ref,
                    nodes,
                    before: reference,
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

    private func insertBlockChildren(
        _ ref: LayoutRef,
        _ nodes: [DOMRef],
        before reference: DOMRef,
        in current: [LayoutID]
    ) -> [LayoutID]? {
        guard blockExtraNodes(ref).isEmpty,
            current.allSatisfy({ LayoutRef(id: $0, tree: self).isBlock })
        else {
            return nil
        }
        guard let index: Int = blockChildIndex(of: reference, in: current) else {
            return nil
        }
        guard !nodes.contains(where: { $0.element?.tag == "h6" }) else {
            return nil
        }
        if index > 0 {
            let previous: LayoutRef = LayoutRef(id: current[index - 1], tree: self)
            if isRunIn(previous) { return nil }
        }
        let referenceBlock: LayoutRef = LayoutRef(id: current[index], tree: self)
        if isRunIn(referenceBlock) {
            return nil
        }
        guard let first: DOMRef = firstVisibleChild(in: nodes) else {
            return current
        }

        let startsInline: Bool = first.style.computed.layout.display != .block
        if startsInline, index > 0 {
            let previous: LayoutRef = LayoutRef(id: current[index - 1], tree: self)
            if !blockExtraNodes(previous).isEmpty {
                return nil
            }
        }

        let prefix: [LayoutID] = Array(current[..<index])
        var state: BlockChildBuild = BlockChildBuild(
            built: prefix,
            previous: lastFlowChild(ref, in: prefix)
        )
        consumeBlockChildren(ref, nodes, state: &state)
        finishBlockChildren(ref, &state)

        var previous: LayoutID? = state.previous
        for id in current[index...] {
            let block: LayoutRef = LayoutRef(id: id, tree: self)
            setBlockPrevious(block, previous)
            let isFlow: Bool = !blockExtraNodes(block).isEmpty
                || block.node.style.computed.layout.position.kind != .absolute
            if isFlow { previous = id }
        }

        var result: [LayoutID] = state.built
        result.append(contentsOf: current[index...])
        return result
    }

    private func blockChildIndex(
        of reference: DOMRef,
        in current: [LayoutID]
    ) -> Int? {
        for (index, id) in current.enumerated() {
            let block: LayoutRef = LayoutRef(id: id, tree: self)
            let extras: [DOMRef] = blockExtraNodes(block)
            if block.domNode == reference.id, extras.isEmpty {
                return index
            }
            if extras.contains(where: { $0.id == reference.id }) {
                return nil
            }
        }
        return nil
    }

    private func isRunIn(_ block: LayoutRef) -> Bool {
        let first: DOMRef = blockExtraNodes(block).first ?? block.node
        return first.element?.tag == "h6"
    }

    private func firstVisibleChild(in nodes: [DOMRef]) -> DOMRef? {
        return nodes.first(where: { child in
            guard let el = child.element else { return true }
            return !LayoutTree.hiddenElements.contains(el.tag)
        })
    }

    private func lastFlowChild(_ ref: LayoutRef, in children: [LayoutID]) -> LayoutID? {
        for id in children.reversed() {
            let child: LayoutRef = LayoutRef(id: id, tree: self)
            if child.isBlock, !blockExtraNodes(child).isEmpty {
                return id
            }
            if child.node.style.computed.layout.position.kind != .absolute {
                return id
            }
        }
        return nil
    }

    private func consumeBlockChildren(
        _ ref: LayoutRef,
        _ nodes: [DOMRef],
        state: inout BlockChildBuild
    ) {
        for child in nodes {
            if let el = child.element, LayoutTree.hiddenElements.contains(el.tag) {
                continue
            }
            let isBlock: Bool = child.style.computed.layout.display == .block
            if isBlock {
                if let el = child.element, el.tag == "h6" {
                    flushInlineRun(ref, &state)
                    state.pendingRunIn = el
                } else {
                    flushInlineRun(ref, &state)
                    if let runIn: ElementRef = state.pendingRunIn {
                        let run: [NodeID] = [runIn.ref.id, child.id]
                        let next: LayoutID = makeAnonymousBlock(
                            extraNodes: run,
                            parent: ref.id,
                            previous: state.previous
                        )
                        state.built.append(next)
                        state.previous = next
                        state.pendingRunIn = nil
                    } else {
                        let next: LayoutID = makeBlock(
                            dom: child.id,
                            parent: ref.id,
                            previous: state.previous
                        )
                        state.built.append(next)
                        if child.style.computed.layout.position.kind != .absolute {
                            state.previous = next
                        }
                    }
                }
            } else {
                state.inlineRun.append(child)
            }
        }
    }

    private func flushInlineRun(_ ref: LayoutRef, _ state: inout BlockChildBuild) {
        guard !state.inlineRun.isEmpty else { return }
        let run: [DOMRef] = state.inlineRun
        let anon: LayoutID = makeAnonymousBlock(
            extraNodes: run.map({ $0.id }),
            parent: ref.id,
            previous: state.previous
        )
        state.built.append(anon)
        state.previous = anon
        state.inlineRun = []
    }

    private func finishBlockChildren(_ ref: LayoutRef, _ state: inout BlockChildBuild) {
        flushInlineRun(ref, &state)
        if let runIn: ElementRef = state.pendingRunIn {
            let next: LayoutID = makeBlock(
                dom: runIn.ref.id,
                parent: ref.id,
                previous: state.previous
            )
            state.built.append(next)
        }
    }

    // MARK: - Padding

    private func paddingValue(_ ref: LayoutRef, _ side: StyleProperty) -> CGFloat {
        let insets: EdgeInsets = ref.node.style.computed.box.spacing.padding
        switch side {
        case .paddingTop: return insets.top
        case .paddingRight: return insets.right
        case .paddingBottom: return insets.bottom
        case .paddingLeft: return insets.left
        default: return 0
        }
    }

    func padding(
        _ ref: LayoutRef,
        _ side: StyleProperty,
        notify: any InvalidatableField
    ) -> CGFloat {
        guard blockExtraNodes(ref).isEmpty else { return 0 }
        ref.node.style.field(side).touch(notify)
        return ref.scaled(max(0, paddingValue(ref, side)))
    }

    private func paintedPadding(_ ref: LayoutRef, _ side: StyleProperty) -> CGFloat {
        guard blockExtraNodes(ref).isEmpty else { return 0 }
        return ref.scaled(max(0, paddingValue(ref, side)))
    }

    func paddingVertical(_ ref: LayoutRef, notify: any InvalidatableField) -> CGFloat {
        return padding(ref, .paddingTop, notify: notify)
            + padding(ref, .paddingBottom, notify: notify)
    }

    func boxHeight(_ ref: LayoutRef, notify: any InvalidatableField) -> CGFloat {
        return ref.heightField.read(notify: notify) + paddingVertical(ref, notify: notify)
    }

    // MARK: - Inline items

    private func placeInlineItems(_ ref: LayoutRef) {
        let items: [InlineItem] = ref.blockData.content.inlineItems
        var placement: InlinePlacement = InlinePlacement(tree: self, parent: ref.id)
        placement.start()
        for (index, item) in items.enumerated() {
            switch item {
            case .lineBreak:
                placement.endLine()
            case .text(let text):
                placeText(ref, text, index: index, into: &placement)
            case .embed(let element):
                placeEmbed(ref, element, index: index, into: &placement)
            }
        }
        placement.finish()
        ref.children = placement.lines.map({ LayoutRef(id: $0, tree: self) })
        profiler.count("layout.lines.total", by: placement.lines.count)
    }

    private func refreshInlineItems(_ ref: LayoutRef) {
        let leaves: [DOMRef] = inlineLeaves(ref)
        var items: [InlineItem] = []
        for leaf in leaves {
            items.append(contentsOf: makeItems(ref, for: leaf))
        }
        var data: BlockData = ref.blockData
        data.content.inlineItems = items
        data.content.inlineObjects.removeAll(keepingCapacity: true)
        data.content.inlineLinePlan = nil
        ref.blockData = data
        let revision: UInt64 = ref.tree.node(ref.id).state.fields.inlineText.inlineContent + 1
        ref.inlineContentField.set(revision)
    }

    private func collectLeaves(_ n: DOMRef, into leaves: inout [DOMRef]) {
        if n.text != nil {
            leaves.append(n)
            return
        }
        guard let el = n.element else { return }
        if el.tag == "br" || isEmbed(el) {
            leaves.append(n)
            return
        }
        for child in n.children { collectLeaves(child, into: &leaves) }
    }

    private func isEmbed(_ el: ElementRef) -> Bool {
        el.tag == "input" || el.tag == "button" || el.tag == "img"
        || el.tag == "iframe" || el.tag == "canvas"
    }

    private func makeItems(_ ref: LayoutRef, for leaf: DOMRef) -> [InlineItem] {
        var items: [InlineItem] = []
        if let text = leaf.text {
            addTextNode(ref, text, into: &items)
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
        _ ref: LayoutRef,
        _ textNode: TextRef,
        into items: inout [InlineItem]
    ) {
        textNode.ref.inheritedStyleOwner.style.field(.whiteSpace).touch(ref.inlineContentField)
        let mode: WhiteSpaceMode = textNode.ref.inheritedStyleOwner.style.computed.text.whiteSpace
        let zoom: CGFloat = ref.zoomField.read(notify: ref.inlineContentField)
        let font: BrowserFont = fontForElement(
            textNode.ref,
            zoom: zoom,
            notify: ref.inlineContentField
        )
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
                addSegment(ref, text: segment, run: run, into: &items)
            }
        } else {
            addSegment(ref, text: textNode.text, run: run, into: &items)
        }
    }

    private func addSegment(
        _ ref: LayoutRef,
        text: String,
        run: InlineTextRun,
        into items: inout [InlineItem]
    ) {
        if run.whiteSpace.keepSpaces {
            if !text.isEmpty { addWord(ref, text, run: run, into: &items) }
        } else {
            for word in text.split(whereSeparator: { $0.isWhitespace }) {
                addWord(ref, String(word), run: run, into: &items)
            }
        }
    }

    private func addWord(
        _ ref: LayoutRef,
        _ word: String,
        run: InlineTextRun,
        into items: inout [InlineItem]
    ) {
        profiler.count("text.words")

        if run.isAbbr && word.contains(where: { $0.isLowercase }) {
            addAbbrWord(ref, run: run, word: word, into: &items)
            return
        }
        items.append(.text(InlineTextItem(run: run, word: word, display: nil)))
    }

    private func placeEmbed(
        _ ref: LayoutRef,
        _ element: ElementRef,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        if placement.currentLine != nil {
            var data: LineData = LayoutRef(id: placement.currentLine!, tree: self).lineData
            data.content.hasEmbed = true
            LayoutRef(id: placement.currentLine!, tree: self).lineData = data
        }
        switch element.tag {
        case "input": addInput(ref, element, index: index, into: &placement)
        case "button": addButton(ref, element, index: index, into: &placement)
        case "img": addImage(ref, element, index: index, into: &placement)
        case "iframe": addIframe(ref, element, index: index, into: &placement)
        case "canvas": addCanvas(ref, element, index: index, into: &placement)
        default: break
        }
    }

    private func placeText(
        _ ref: LayoutRef,
        _ item: InlineTextItem,
        index: Int?,
        into placement: inout InlinePlacement
    ) {
        let font: BrowserFont = item.fontOverride ?? item.run.font
        let measured: CGFloat = item.measuredWidth ?? font.measure(item.display ?? item.word)
        let w: CGFloat = measured + font.spaceWidth
        if placement.cursorX + w > ref.width && item.run.whiteSpace.wraps {
            if item.word.contains("\u{00AD}") {
                let parts: [String] = item.word.components(separatedBy: "\u{00AD}")
                var chunk: String = ""
                var breakIdx: Int = -1
                for (i, part) in parts.dropLast().enumerated() {
                    let candidate: String = chunk + part + "-"
                    if placement.cursorX + font.measure(candidate) <= ref.width {
                        chunk = chunk + part
                        breakIdx = i
                    }
                }
                if breakIdx >= 0 {
                    appendToLine(ref, clone(item, word: chunk + "-"), index: nil, into: &placement)
                    placement.endLine()
                    placeText(
                        ref,
                        clone(item, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}")),
                        index: nil,
                        into: &placement
                    )
                    return
                }
            }
            placement.endLine()
        }

        appendToLine(ref, item, index: index, into: &placement)
        placement.cursorX += w
    }

    private func appendToLine(
        _ ref: LayoutRef,
        _ item: InlineTextItem,
        index: Int?,
        into placement: inout InlinePlacement
    ) {
        let font: BrowserFont = item.fontOverride ?? item.run.font
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let text: LayoutID
        if let index,
            let cached: LayoutID = cachedText(ref, at: index, node: item.run.node, word: item.word)
        {
            text = cached
            attachText(LayoutRef(id: cached, tree: self), to: lineID, previous: previous)
        } else {
            text = makeText(
                TextData(
                    word: item.word,
                    display: item.display,
                    fontOverride: item.fontOverride,
                    metrics: TextMetrics(width: 0, whiteSpace: item.run.whiteSpace)
                ),
                dom: item.run.node.id,
                parent: lineID,
                previous: previous
            )
            LayoutRef(id: text, tree: self).font = font
            if let index {
                var data: BlockData = ref.blockData
                data.content.inlineObjects[index] = text
                ref.blockData = data
            }
        }
        placement.append(text)
    }

    private func clone(_ item: InlineTextItem, word: String) -> InlineTextItem {
        InlineTextItem(
            run: item.run,
            word: word,
            display: nil,
            fontOverride: item.fontOverride
        )
    }

    private func addInput(
        _ ref: LayoutRef,
        _ node: ElementRef,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        if node.attributes["type"] == "hidden" { return }

        let available: CGFloat = ref.widthField.get()
        let zoom: CGFloat = ref.zoomField.read(notify: ref.childrenField)
        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: ref.childrenField)
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : inputWidthPx * zoom
        if placement.cursorX + w > available { placement.endLine() }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let input: LayoutID
        if let cached: LayoutID = cachedEmbed(ref, .input, at: index, node: node) {
            input = cached
            attachEmbed(LayoutRef(id: cached, tree: self), to: lineID, previous: previous)
        } else {
            input = makeEmbed(dom: node.ref.id, data: .input, parent: lineID, previous: previous)
            var data: BlockData = ref.blockData
            data.content.inlineObjects[index] = input
            ref.blockData = data
        }
        placement.append(input)

        placement.cursorX += w + font.spaceWidth
    }

    private func addButton(
        _ ref: LayoutRef,
        _ node: ElementRef,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = ref.widthField.get()
        let zoom: CGFloat = ref.zoomField.read(notify: ref.childrenField)
        let w: CGFloat = inputWidthPx * zoom
        if placement.cursorX + w > available { placement.endLine() }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let button: LayoutID
        if let cached: LayoutID = cachedEmbed(ref, .button, at: index, node: node) {
            button = cached
            attachEmbed(LayoutRef(id: cached, tree: self), to: lineID, previous: previous)
        } else {
            button = makeEmbed(
                dom: node.ref.id,
                data: .button(ButtonData(cursorX: 0)),
                parent: lineID,
                previous: previous
            )
            var data: BlockData = ref.blockData
            data.content.inlineObjects[index] = button
            ref.blockData = data
        }
        placement.append(button)
        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: ref.childrenField)
        placement.cursorX += w + font.spaceWidth
    }

    private func addImage(
        _ ref: LayoutRef,
        _ node: ElementRef,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = ref.widthField.get()
        let zoom: CGFloat = ref.zoomField.read(notify: ref.childrenField)
        let w: CGFloat = imageUsedWidth(
            for: node,
            available: available,
            zoom: zoom,
            notify: ref.childrenField
        )
        if placement.cursorX + w > available { placement.endLine() }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let image: LayoutID
        if let cached: LayoutID = cachedEmbed(ref, .image, at: index, node: node) {
            image = cached
            let imageRef: LayoutRef = LayoutRef(id: cached, tree: self)
            attachEmbed(imageRef, to: lineID, previous: previous)
            attachImage(imageRef, to: lineID)
        } else {
            image = makeEmbed(
                dom: node.ref.id,
                data: .image(ImageData(imageHeight: 0)),
                parent: lineID,
                previous: previous
            )
            var data: BlockData = ref.blockData
            data.content.inlineObjects[index] = image
            ref.blockData = data
        }
        placement.append(image)

        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: ref.childrenField)
        placement.cursorX += w + font.spaceWidth
    }

    private func addIframe(
        _ ref: LayoutRef,
        _ node: ElementRef,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = ref.widthField.get()
        let zoom: CGFloat = ref.zoomField.read(notify: ref.childrenField)
        let w: CGFloat = iframeDisplaySize(for: node, notify: ref.childrenField).width * zoom
        if placement.cursorX + w > available { placement.endLine() }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let iframe: LayoutID
        if let cached: LayoutID = cachedEmbed(ref, .iframe, at: index, node: node) {
            iframe = cached
            attachEmbed(LayoutRef(id: cached, tree: self), to: lineID, previous: previous)
        } else {
            iframe = makeEmbed(
                dom: node.ref.id,
                data: .iframe,
                parent: lineID,
                previous: previous
            )
            var data: BlockData = ref.blockData
            data.content.inlineObjects[index] = iframe
            ref.blockData = data
        }
        placement.append(iframe)

        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: ref.childrenField)
        placement.cursorX += w + font.spaceWidth
    }

    private func addCanvas(
        _ ref: LayoutRef,
        _ node: ElementRef,
        index: Int,
        into placement: inout InlinePlacement
    ) {
        let available: CGFloat = ref.widthField.get()
        let zoom: CGFloat = ref.zoomField.read(notify: ref.childrenField)
        let w: CGFloat = canvasContentSize(for: node).width * zoom
        if placement.cursorX + w > available { placement.endLine() }
        guard let lineID: LayoutID = placement.currentLine else { return }
        let previous: LayoutID? = placement.children.last
        let canvas: LayoutID
        if let cached: LayoutID = cachedEmbed(ref, .canvas, at: index, node: node) {
            canvas = cached
            attachEmbed(LayoutRef(id: cached, tree: self), to: lineID, previous: previous)
        } else {
            canvas = makeEmbed(
                dom: node.ref.id,
                data: .canvas,
                parent: lineID,
                previous: previous
            )
            var data: BlockData = ref.blockData
            data.content.inlineObjects[index] = canvas
            ref.blockData = data
        }
        placement.append(canvas)

        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: ref.childrenField)
        placement.cursorX += w + font.spaceWidth
    }

    private func isInsideAbbr(_ node: DOMRef) -> Bool {
        var current: DOMRef? = node.parent
        while let c = current {
            if let el = c.element, el.tag == "abbr" { return true }
            current = c.parent
        }
        return false
    }

    private func addAbbrWord(
        _ ref: LayoutRef,
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

        let node: DOMRef = run.node
        let owner: DOMRef = node.inheritedStyleOwner
        owner.style.field(.fontWeight).touch(ref.inlineContentField)
        owner.style.field(.fontStyle).touch(ref.inlineContentField)
        owner.style.field(.fontSize).touch(ref.inlineContentField)
        owner.style.field(.fontFamily).touch(ref.inlineContentField)
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
        _ ref: LayoutRef,
        at index: Int,
        node: DOMRef,
        word: String
    ) -> LayoutID? {
        guard let id: LayoutID = ref.blockData.content.inlineObjects[index] else { return nil }
        guard contains(id) else { return nil }
        let candidate: LayoutRef = LayoutRef(id: id, tree: self)
        guard candidate.isText,
            candidate.domNode == node.id,
            candidate.textData.word == word
        else { return nil }
        return id
    }

    private func cachedEmbed(
        _ ref: LayoutRef,
        _ kind: EmbedMatch,
        at index: Int,
        node: ElementRef
    ) -> LayoutID? {
        guard let id: LayoutID = ref.blockData.content.inlineObjects[index] else { return nil }
        guard contains(id) else { return nil }
        let candidate: LayoutRef = LayoutRef(id: id, tree: self)
        guard candidate.isEmbed,
            candidate.domNode == node.ref.id,
            kind.matches(candidate.embedData)
        else { return nil }
        return id
    }

    // MARK: - Paint

    func blockSelfRect(_ ref: LayoutRef) -> Rect {
        let top: CGFloat = paintedPadding(ref, .paddingTop)
        let right: CGFloat = paintedPadding(ref, .paddingRight)
        let bottom: CGFloat = paintedPadding(ref, .paddingBottom)
        let left: CGFloat = paintedPadding(ref, .paddingLeft)
        return Rect(
            left: ref.x - left,
            top: ref.y - top,
            right: ref.x + ref.width + right,
            bottom: ref.y + ref.height + bottom
        )
    }

    private func borderPaintRect(_ ref: LayoutRef) -> Rect {
        let rect: Rect = blockSelfRect(ref)
        let width: CGFloat = ref.node.style.computed.box.decoration.border.width
        guard width > 0 else { return rect }
        let half: CGFloat = width / 2
        return Rect(
            left: rect.left - half,
            top: rect.top - half,
            right: rect.right + half,
            bottom: rect.bottom + half
        )
    }

    func paintBlock(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        let computed: ComputedStyle = ref.node.style.computed
        let background: BrowserColor? = computed.visual.background.color
        if background != nil || computed.layout.overflow == .scroll {
            let radii: CornerRadii = computed.box.decoration.border.radii
            let color: BrowserColor = background ?? BrowserColor(
                red: 0, green: 0, blue: 0, alpha: 0
            )
            if !radii.isZero {
                items.append(.rrect(rect: blockSelfRect(ref), radii: radii, color: color))
            } else {
                items.append(.rect(rect: blockSelfRect(ref), color: color))
            }
        }

        if let el = ref.node.element, let image = el.backgroundImage,
            computed.visual.background.image != nil {
            let box: Rect = blockSelfRect(ref)
            let dest: Rect = BackgroundSize(box: box, image: image, zoom: ref.zoom)
                .rect(spec: computed.visual.background.size)
            items.append(.clippedImage(
                image: image,
                rendering: computed.visual.image.rendering,
                rect: dest,
                clip: box
            ))
        }

        if let border: DisplayOp = DisplayOp.fromBorderStyle(ref.node, rect: borderPaintRect(ref)) {
            items.append(border)
        }

        let outline: DisplayOp? = DisplayOp.fromStyle(ref.node, rect: blockSelfRect(ref))
        if ref.node.isFocusVisible && outline == nil {
            let ring: (outer: String, inner: String) = focusRingColors(ref.node)
            items.append(.outline(rect: blockSelfRect(ref), color: BrowserColor(cssName: ring.outer), width: 4))
            items.append(.outline(rect: blockSelfRect(ref), color: BrowserColor(cssName: ring.inner), width: 2))
        }
        if let outline = outline { items.append(outline) }

        if let el = ref.node.element, el.tag == "li" {
            let bulletX: CGFloat = ref.x - LayoutTree.liIndent
            let bulletY: CGFloat = ref.y + (VSTEP - LayoutTree.bulletSize) / 2
            let bulletRect: Rect = Rect(
                left: bulletX, top: bulletY, right: bulletX + LayoutTree.bulletSize,
                bottom: bulletY + LayoutTree.bulletSize
            )
            items.append(.rect(rect: bulletRect, color: BrowserColor(cssName: usesForcedColors(ref.node) ? ForcedColor.canvasText : "black")))
        }
    }

    func blockPaintCaret(_ ref: LayoutRef, into items: inout [DisplayOp]) {
        guard let el = ref.node.element, el.isFocused,
            el.attributes["contenteditable"] != nil
        else { return }
        if let last: LayoutRef = lastTextLayout(ref) {
            items.append(drawCursor(last, offset: textTextWidth(last)))
        } else {
            items.append(drawCursor(ref, offset: 0))
        }
    }

    func blockPaintScrollbar(_ ref: LayoutRef) -> [DisplayOp] {
        let scroll: BlockScroll = ref.blockData.scroll
        guard ref.node.style.computed.layout.overflow == .scroll,
            scroll.contentHeight > ref.height
        else { return [] }
        let barWidth: CGFloat = 8
        let ratio: CGFloat = ref.height / scroll.contentHeight
        let barHeight: CGFloat = ratio * ref.height
        let barTop: CGFloat = ref.y + (scroll.offset / scroll.contentHeight) * ref.height
        let barRect: Rect = Rect(
            left: ref.x + ref.width - barWidth, top: barTop,
            right: ref.x + ref.width, bottom: barTop + barHeight)
        return [.rect(rect: barRect, color: BrowserColor(cssName: usesForcedColors(ref.node) ? ForcedColor.canvasText : "gray"))]
    }

    func blockShouldPaint(_ ref: LayoutRef) -> Bool {
        if ref.node.text != nil { return true }
        guard let el = ref.node.element else { return true }
        return el.tag != "input" && el.tag != "button" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas"
    }

    func blockStyle(_ ref: LayoutRef) -> BlockStyle {
        let revision: UInt64 = ref.node.style.revision
        let paint: BlockPaint = ref.blockData.paint
        if let cachedStyle = paint.style, paint.styleRevision == revision {
            profiler.count("layout.block.style.cache.hit")
            return cachedStyle
        }
        profiler.count("layout.block.style.cache.miss")
        let style: BlockStyle = BlockStyle(node: ref.node)
        var data: BlockData = ref.blockData
        data.paint.style = style
        data.paint.styleRevision = revision
        ref.blockData = data
        return style
    }

    // MARK: - Cursor

    private func lastTextLayout(_ ref: LayoutRef) -> LayoutRef? {
        for child in ref.children.reversed() {
            if child.isText { return child }
            if let nested: LayoutRef = lastTextLayout(child) { return nested }
        }
        return nil
    }

    // MARK: - Scroll

    func blockScrollOffset(_ ref: LayoutRef) -> CGFloat {
        return ref.blockData.scroll.offset
    }

    func setBlockScrollOffset(_ ref: LayoutRef, _ value: CGFloat) {
        var data: BlockData = ref.blockData
        data.scroll.offset = value
        ref.blockData = data
    }

    func blockContentHeight(_ ref: LayoutRef) -> CGFloat {
        return ref.blockData.scroll.contentHeight
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

// Mutable cursor for one pass of the block child builder.
private struct BlockChildBuild {
    var built: [LayoutID] = []
    var previous: LayoutID?
    var inlineRun: [DOMRef] = []
    var pendingRunIn: ElementRef?
}

// MARK: - Inline placement

@MainActor
private struct InlinePlacementContext {
    let tree: LayoutTree
    let parent: LayoutID
}

private struct InlinePlacementState {
    var lines: [LayoutID] = []
    var currentLine: LayoutID? = nil
    var children: [LayoutID] = []
    var cursorX: CGFloat = 0
}

@MainActor
struct InlinePlacement {
    private let context: InlinePlacementContext
    private var state: InlinePlacementState = InlinePlacementState()

    init(tree: LayoutTree, parent: LayoutID) {
        self.context = InlinePlacementContext(tree: tree, parent: parent)
    }

    var lines: [LayoutID] { state.lines }
    var currentLine: LayoutID? { state.currentLine }
    var children: [LayoutID] { state.children }
    var cursorX: CGFloat {
        get { state.cursorX }
        set { state.cursorX = newValue }
    }

    mutating func start() {
        let previous: LayoutID? = state.lines.last
        state.currentLine = context.tree.makeLine(
            dom: context.tree.node(context.parent).dom,
            parent: context.parent,
            previous: previous
        )
        state.children = []
        state.cursorX = 0
    }

    mutating func endLine() {
        guard let line: LayoutID = state.currentLine else { return }
        LayoutRef(id: line, tree: context.tree).children =
            state.children.map({ LayoutRef(id: $0, tree: context.tree) })
        state.lines.append(line)
        start()
    }

    mutating func finish() {
        guard let line: LayoutID = state.currentLine else { return }
        LayoutRef(id: line, tree: context.tree).children =
            state.children.map({ LayoutRef(id: $0, tree: context.tree) })
        state.lines.append(line)
        state.currentLine = nil
        state.children = []
    }

    mutating func append(_ child: LayoutID) {
        state.children.append(child)
    }
}


extension LayoutRef {
    func blockStyle() -> BlockStyle {
        return tree.blockStyle(self)
    }

    func padding(_ side: StyleProperty, notify: any InvalidatableField) -> CGFloat {
        return tree.padding(self, side, notify: notify)
    }
}
