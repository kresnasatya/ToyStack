import CoreGraphics

// MARK: - BlockLayout
@MainActor
class BlockLayout: LayoutObject {
    static let hiddenElements: Set<String> = ["head", "title", "script", "style"]

    static let liIndent: CGFloat = 20.0
    static let bulletSize: CGFloat = 8.0

    let node: DOMRef
    var parent: (any LayoutObject)?
    let fields: LayoutFieldStore = LayoutFieldStore()
    var previous: (any LayoutObject)? {
        get { previousField.get() }
        set { setPrevious(newValue) }
    }
    var hasDirtyDescendants: Bool = false
    private var childChanges: [BlockChildChange] = []
    let extraNodes: [DOMRef]
    var paintCache: PaintCache = PaintCache()
    private var cachedStyle: BlockStyle? = nil
    private var cachedStyleRevision: UInt64 = .max

    private var inlineItems: [InlineItem] = []
    private var inlineContentRevision: UInt64 = 0
    private var inlineObjects: [Int: any LayoutObject] = [:]
    private var inlineLinePlan: [[Int]]? = nil

    var scrollOffset: CGFloat = 0
    var contentHeight: CGFloat = 0

    private var declaredHeightChildren: [any LayoutObject] = []

    init(node: DOMRef, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.extraNodes = []
        self.parent = parent
        node.layoutObject = self
        previousField.setClean(previous)
        previousField.setDependencies([])
        markAncestorsDirty()
        freezeGeometry(parent: parent, previous: previous)
    }

    init(nodes: [DOMRef], parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = nodes[0]
        self.extraNodes = nodes
        self.parent = parent
        previousField.setClean(previous)
        previousField.setDependencies([])
        markAncestorsDirty()
        freezeGeometry(parent: parent, previous: previous)
    }

    private var previousField: LayoutFieldHandle<PreviousFieldAccess> {
        layoutField(.previous)
    }

    private func freezeGeometry(parent: any LayoutObject, previous: (any LayoutObject)?) {
        zoomField.setDependencies([parent.zoomField, node.style.field(.zoom)])
        xField.setDependencies([
            parent.xField,
            zoomField,
            node.style.field(.paddingLeft),
            node.style.field(.position),
            node.style.field(.left),
        ])
        var yInputs: [any InvalidatableField] = [
            parent.yField,
            previousField,
            zoomField,
            node.style.field(.paddingTop),
            node.style.field(.top),
            node.style.field(.marginTop),
        ]
        if let previous {
            yInputs.append(previous.yField)
            yInputs.append(previous.heightField)
            yInputs.append(previous.node.style.field(.marginBottom))
            yInputs.append(previous.node.style.field(.paddingBottom))
        }
        yField.setDependencies(yInputs)
        widthField.setDependencies([
            parent.widthField,
            zoomField,
            node.style.field(.paddingLeft),
            node.style.field(.paddingRight),
            node.style.field(.width),
        ])
        let contentInputs: [any InvalidatableField] = inlineContentInputs()
        inlineContentField.setDependencies(contentInputs)
        childrenField.setDependencies(contentInputs + [inlineContentField])
    }

    private func inlineContentInputs() -> [any InvalidatableField] {
        var inputs: [any InvalidatableField] = [
            zoomField,
            node.style.field(.display),
            node.style.field(.position),
            node.style.field(.direction),
        ]
        if extraNodes.isEmpty {
            for child in node.children {
                inputs.append(child.style.field(.display))
                inputs.append(child.style.field(.position))
            }
        }
        let leaves: [DOMRef] = inlineLeaves()
        for leaf in leaves {
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
    private func inlineLeaves() -> [DOMRef] {
        var leaves: [DOMRef] = []
        if !extraNodes.isEmpty {
            for n in extraNodes { collectLeaves(n, into: &leaves) }
            return leaves
        }
        let hasBlockChild: Bool = node.children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if !hasBlockChild {
            collectLeaves(node, into: &leaves)
            return leaves
        }
        for child in node.children where child.style.computed.layout.display != .block {
            collectLeaves(child, into: &leaves)
        }
        return leaves
    }

    private func inlineTextLinePlan() -> [[Int]]? {
        var plan: [[Int]] = []
        var current: [Int] = []
        var cursorX: CGFloat = 0
        let availableWidth: CGFloat = width

        for index in inlineItems.indices {
            switch inlineItems[index] {
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
                    inlineItems[index] = .text(text)
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

        plan.append(current)
        return plan
    }

    private func setHeightInputs() {
        let unchanged: Bool = children.count == declaredHeightChildren.count && zip(children, declaredHeightChildren).allSatisfy({ $0 === $1 })
        if unchanged { return }
        declaredHeightChildren = children
        var inputs: [any InvalidatableField] = [
            childrenField,
            zoomField,
            node.style.field(.height),
            node.style.field(.overflow),
        ]
        for child in children {
            inputs.append(child.heightField)
            inputs.append(child.node.style.field(.position))
            inputs.append(child.node.style.field(.marginTop))
            inputs.append(child.node.style.field(.marginBottom))
            if child is BlockLayout {
                inputs.append(child.zoomField)
                inputs.append(child.node.style.field(.paddingTop))
                inputs.append(child.node.style.field(.paddingBottom))
            }
        }
        heightField.setDependencies(inputs)
    }

    func markChildrenDirty() {
        childChanges.removeAll()
        inlineContentField.mark()
        childrenField.mark()
    }

    func noteAppendedChildren(_ nodes: [any DOMNode]) {
        childChanges.append(.append(nodes.map({ node.dom.ref($0) })))
        markAncestorsDirty()
    }

    func noteInsertedChildren(_ nodes: [any DOMNode], before reference: any DOMNode) {
        childChanges.append(.insert(nodes.map({ node.dom.ref($0) }), before: node.dom.ref(reference)))
        markAncestorsDirty()
    }

    private func setPrevious(_ newValue: (any LayoutObject)?) {
        previousField.set(newValue)
        guard let newValue else { return }
        yField.setDependencies([
            newValue.yField,
            newValue.heightField,
            newValue.node.style.field(.marginBottom),
            newValue.node.style.field(.paddingBottom),
        ])
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        let fields: LayoutFieldStore = self.fields
        if fields.isDirty(.zoom) || fields.isDirty(.x) || fields.isDirty(.y)
            || fields.isDirty(.width) || fields.isDirty(.height)
        {
            return true
        }

        return fields.isDirty(.inlineContent) || fields.isDirty(.children) || !childChanges.isEmpty
    }

    func layout() {
        if !layoutNeeded() {
            profiler.count("layout.skipped")
            return
        }
        defer { hasDirtyDescendants = false }
        profiler.count("layout.visited")
        // A display change moves children between the block and inline paths, so
        // the leaves that inline layout will read were not known when the block
        // was built. Re-declare them before this pass reads them.
        if fields.isDirty(.inlineContent) || fields.isDirty(.children) || !childChanges.isEmpty {
            let contentInputs: [any InvalidatableField] = inlineContentInputs()
            inlineContentField.setDependencies(contentInputs)
            childrenField.setDependencies(contentInputs + [inlineContentField])
        }

        let style: BlockStyle = blockStyle()
        profiler.measure("layout.visit") {
            profiler.count("layout.rebuilt")
            zoom = resolvedZoom()
            let isAbsolute: Bool = style.position == .absolute

            let parentX: CGFloat = parent!.xField.read(notify: xField)
            let padLeft: CGFloat = extraNodes.isEmpty ? style.box.padding.left * zoom : 0
            if isAbsolute, let l = style.flags.left {
                let absoluteXZoom: CGFloat = zoomField.read(notify: xField)
                xField.set(l * absoluteXZoom + padLeft)
            } else {
                xField.set(parentX + padLeft)
            }

            let parentWidth: CGFloat = parent!.widthField.read(notify: widthField)
            let zoom: CGFloat = zoomField.read(notify: widthField)
            let padHorizontal: CGFloat = extraNodes.isEmpty ? (style.box.padding.left + style.box.padding.right) * zoom : 0
            if let w = style.box.width {
                widthField.set(w * zoom)
            } else {
                widthField.set(max(0, parentWidth - padHorizontal))
            }

            if let el = node.element, el.tag == "li" {
                x += BlockLayout.liIndent
                width -= BlockLayout.liIndent
            }

            if isAbsolute, let t = style.flags.top {
                let absoluteYZoom: CGFloat = zoomField.read(notify: yField)
                let padTop: CGFloat = extraNodes.isEmpty ? style.box.padding.left * zoom : 0
                yField.set(t * absoluteYZoom + padTop)
            } else {
                let ownTop: CGFloat = style.box.margin.top * zoom
                let padTop: CGFloat = style.box.padding.top * zoom
                if let prev = previous {
                    let prevY: CGFloat = prev.yField.read(notify: yField)
                    let prevHeight: CGFloat = prev.heightField.read(notify: yField)
                    let prevPadBottom: CGFloat = (prev as? BlockLayout)?.padding(.paddingBottom, notify: yField) ?? 0
                    yField.set(
                        prevY + prevHeight + prevPadBottom
                            + ((prev as? BlockLayout)?.blockStyle().box.margin.bottom ?? 0) * zoom
                            + ownTop + padTop
                    )
                } else {
                    yField.copy(from: parent!.yField)
                    yField.set(yField.get() + ownTop + padTop)
                }
            }

            if let el = node.element, el.attributes["id"] == "toc" {
                y += VSTEP
            }

            let mode: String = profiler.measure("layout.mode", { layoutMode() })
            if mode == "block" {
                profiler.count("layout.mode.block")
                if fields.isDirty(.children) {
                    childrenField.set(rebuildBlockChildren())
                } else if !childChanges.isEmpty {
                    let changes: [BlockChildChange] = childChanges
                    childChanges.removeAll()
                    if let changed: [any LayoutObject] = applyBlockChanges(changes) {
                        countChildChanges(changes)
                        childrenField.set(changed)
                    } else {
                        childrenField.set(rebuildBlockChildren())
                    }
                }

                if fields.isDirty(.inlineContent) {
                    inlineContentRevision += 1
                    inlineContentField.setClean(inlineContentRevision)
                    inlineObjects.removeAll(keepingCapacity: true)
                    inlineLinePlan = nil
                }
            } else {
                profiler.count("layout.mode.inline")
                let inlineContentChanged: Bool = fields.isDirty(.inlineContent) || !childChanges.isEmpty
                childChanges.removeAll()
                _ = zoomField.read(notify: childrenField)
                node.style.field(.direction).touch(childrenField)
                if inlineContentChanged {
                    profiler.measure("layout.inline.refresh", { refreshInlineItems() })
                }
                let plan: [[Int]]? = inlineTextLinePlan()
                let shouldPlace: Bool = inlineContentChanged || plan == nil || plan != inlineLinePlan
                if shouldPlace {
                    profiler.measure("layout.inline.place", { placeInlineItems() })
                } else {
                    childrenField.set(childrenField.peek() ?? [])
                }
                inlineLinePlan = plan
            }
        }

        for child in children { child.layout() }

        setHeightInputs()
        let heightChildren: [any LayoutObject] = childrenField.read(notify: heightField)
        let sumHeight: Double = profiler.measure("layout.height", {
            heightChildren.reduce(0) { total, child in
                child.node.style.field(.position).touch(heightField)
                let position: LayoutStyle.Position = child.node.style.computed.layout.position.kind
                if position == .absolute { return total }
                var h: CGFloat = child.heightField.read(notify: heightField)
                if let block = child as? BlockLayout {
                    let childStyle: BlockStyle = block.blockStyle()
                    let childZoom: CGFloat = child.zoomField.read(notify: heightField)
                    h += (childStyle.box.padding.top + childStyle.box.padding.bottom) * childZoom
                    h += (childStyle.box.margin.top + childStyle.box.margin.bottom) * childZoom
                }
                return total + h
            }
        })

        node.style.field(.height).touch(heightField)
        if let h: CGFloat = node.style.computed.box.size.height {
            contentHeight = sumHeight
            let styleHeightZoom: CGFloat = zoomField.read(notify: heightField)
            heightField.set(h * styleHeightZoom)
        } else {
            contentHeight = sumHeight
            heightField.set(sumHeight)
        }

        if let el = node.element, el.attributes["id"] == "toc" {
            height += VSTEP
        }

        if style.flags.overflowScroll, let el = node.element {
            let maxScroll: CGFloat = max(0, contentHeight - height)
            scrollOffset = min(el.scrollOffsetY, maxScroll)
        }
    }

    private func layoutMode() -> String {
        if !extraNodes.isEmpty { return "inline" }
        if node.text != nil { return "inline" }
        let hasBlockChild: Bool = node.children.contains(where: {
            $0.style.computed.layout.display == .block
        })
        if hasBlockChild { return "block" }
        if let el = node.element {
            return (el.children.isEmpty && el.tag != "input" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas") ? "block" : "inline"
        }
        return "inline"
    }

    private func rebuildBlockChildren() -> [any LayoutObject] {
        profiler.count("layout.children.rebuilt")
        childChanges.removeAll()
        var state: BlockChildBuild = BlockChildBuild()
        consumeBlockChildren(node.children, state: &state)
        finishBlockChildren(&state)
        return state.built
    }

    private func appendBlockChildren(_ nodes: [DOMRef], to current: [any LayoutObject]) -> [any LayoutObject]? {
        guard extraNodes.isEmpty, current.allSatisfy({ $0 is BlockLayout }) else {
            return nil
        }
        if let last: BlockLayout = current.last as? BlockLayout,
            last.extraNodes.isEmpty,
            last.node.element?.tag == "h6"
        {
            return nil
        }
        guard let first: DOMRef = firstVisibleChild(in: nodes) else {
            return nil
        }

        var state: BlockChildBuild = BlockChildBuild(
            built: current,
            previous: lastFlowChild(in: current)
        )
        let startsInline: Bool = first.style.computed.layout.display != .block
        if startsInline,
            let last: BlockLayout = state.built.last as? BlockLayout,
            !last.extraNodes.isEmpty,
            last.extraNodes.allSatisfy({ $0.style.computed.layout.display != .block })
        {
            state.built.removeLast()
            state.inlineRun = last.extraNodes
            state.previous = last.previous
        }

        consumeBlockChildren(nodes, state: &state)
        finishBlockChildren(&state)
        return state.built
    }

    private func applyBlockChanges(_ changes: [BlockChildChange]) -> [any LayoutObject]? {
        var current: [any LayoutObject] = children
        for change in changes {
            switch change {
            case .append(let nodes):
                guard let next: [any LayoutObject] = appendBlockChildren(nodes, to: current) else {
                    return nil
                }
                current = next
            case .insert(let nodes, let reference):
                guard let next: [any LayoutObject] = insertBlockChildren(
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
        _ nodes: [DOMRef],
        before reference: DOMRef,
        in current: [any LayoutObject]
    ) -> [any LayoutObject]? {
        guard extraNodes.isEmpty, current.allSatisfy({ $0 is BlockLayout }) else {
            return nil
        }
        guard let index: Int = blockChildIndex(of: reference, in: current) else {
            return nil
        }
        guard !nodes.contains(where: { $0.element?.tag == "h6" }) else {
            return nil
        }
        if index > 0, let previous = current[index - 1] as? BlockLayout, isRunIn(previous) {
            return nil
        }
        if let referenceBlock = current[index] as? BlockLayout, isRunIn(referenceBlock) {
            return nil
        }
        guard let first: DOMRef = firstVisibleChild(in: nodes) else {
            return current
        }

        let startsInline: Bool = first.style.computed.layout.display != .block
        if startsInline, index > 0,
            let previous = current[index - 1] as? BlockLayout,
            !previous.extraNodes.isEmpty
        {
            return nil
        }

        let prefix: [any LayoutObject] = Array(current[..<index])
        var state: BlockChildBuild = BlockChildBuild(
            built: prefix,
            previous: lastFlowChild(in: prefix)
        )
        consumeBlockChildren(nodes, state: &state)
        finishBlockChildren(&state)

        var previous: (any LayoutObject)? = state.previous
        for object in current[index...] {
            guard let block = object as? BlockLayout else { return nil }
            block.previous = previous
            let isFlow: Bool = !block.extraNodes.isEmpty
                || block.node.style.computed.layout.position.kind != .absolute
            if isFlow { previous = block }
        }

        var result: [any LayoutObject] = state.built
        result.append(contentsOf: current[index...])
        return result
    }

    private func blockChildIndex(
        of reference: DOMRef,
        in current: [any LayoutObject]
    ) -> Int? {
        for (index, object) in current.enumerated() {
            guard let block = object as? BlockLayout else { return nil }
            if block.node.id == reference.id, block.extraNodes.isEmpty {
                return index
            }
            if block.extraNodes.contains(where: { $0.id == reference.id }) {
                return nil
            }
        }
        return nil
    }

    private func isRunIn(_ block: BlockLayout) -> Bool {
        let first: DOMRef = block.extraNodes.first ?? block.node
        return first.element?.tag == "h6"
    }

    private func firstVisibleChild(in nodes: [DOMRef]) -> DOMRef? {
        return nodes.first(where: { child in
            guard let el = child.element else { return true }
            return !BlockLayout.hiddenElements.contains(el.tag)
        })
    }

    private func lastFlowChild(in children: [any LayoutObject]) -> (any LayoutObject)? {
        for child in children.reversed() {
            if let block = child as? BlockLayout, !block.extraNodes.isEmpty {
                return child
            }
            if child.node.style.computed.layout.position.kind != .absolute {
                return child
            }
        }
        return nil
    }

    private func consumeBlockChildren(_ nodes: [DOMRef], state: inout BlockChildBuild) {
        for child in nodes {
            if let el = child.element, BlockLayout.hiddenElements.contains(el.tag) {
                continue
            }
            let isBlock: Bool = child.style.computed.layout.display == .block
            if isBlock {
                if let el = child.element, el.tag == "h6" {
                    flushInlineRun(into: &state)
                    state.pendingRunIn = el
                } else {
                    flushInlineRun(into: &state)
                    if let runIn = state.pendingRunIn {
                        let run: [DOMRef] = [runIn.ref, child]
                        let next: BlockLayout = BlockLayout(nodes: run, parent: self, previous: state.previous)
                        state.built.append(next)
                        state.previous = next
                        state.pendingRunIn = nil
                    } else {
                        let next: BlockLayout = BlockLayout(node: child, parent: self, previous: state.previous)
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

    private func flushInlineRun(into state: inout BlockChildBuild) {
        guard !state.inlineRun.isEmpty else { return }
        let run: [DOMRef] = state.inlineRun
        let anon: BlockLayout = BlockLayout(nodes: run, parent: self, previous: state.previous)
        state.built.append(anon)
        state.previous = anon
        state.inlineRun = []
    }

    private func finishBlockChildren(_ state: inout BlockChildBuild) {
        flushInlineRun(into: &state)
        if let runIn = state.pendingRunIn {
            let next: BlockLayout = BlockLayout(node: runIn.ref, parent: self, previous: state.previous)
            state.built.append(next)
        }
    }

    // MARK: - Padding

    private func padding(_ side: StyleProperty, notify: any InvalidatableField) -> CGFloat {
        guard extraNodes.isEmpty else { return 0 }
        node.style.field(side).touch(notify)
        return scaled(max(0, paddingValue(side)))
    }

    private func paintedPadding(_ side: StyleProperty) -> CGFloat {
        guard extraNodes.isEmpty else { return 0 }
        return scaled(max(0, paddingValue(side)))
    }

    private func paddingValue(_ side: StyleProperty) -> CGFloat {
        let insets: EdgeInsets = node.style.computed.box.spacing.padding
        switch side {
        case .paddingTop: return insets.top
        case .paddingRight: return insets.right
        case .paddingBottom: return insets.bottom
        case .paddingLeft: return insets.left
        default: return 0
        }
    }

    func paddingVertical(notify: any InvalidatableField) -> CGFloat {
        padding(.paddingTop, notify: notify) + padding(.paddingBottom, notify: notify)
    }

    func boxHeight(notify: any InvalidatableField) -> CGFloat {
        heightField.read(notify: notify) + paddingVertical(notify: notify)
    }

    // MARK: - Inline items

    private func placeInlineItems() {
        var placement: InlinePlacement = InlinePlacement()
        placement.start(parent: self)
        for (index, item) in inlineItems.enumerated() {
            switch item {
            case .lineBreak:
                placement.endLine(parent: self)
            case .text(let text):
                placeText(text, index: index, into: &placement)
            case .embed(let element):
                placeEmbed(element, index: index, into: &placement)
            }
        }
        placement.finish()
        children = placement.lines
        profiler.count("layout.lines.total", by: children.count)
    }

    private func refreshInlineItems() {
        let leaves: [DOMRef] = inlineLeaves()
        var items: [InlineItem] = []
        for leaf in leaves {
            items.append(contentsOf: makeItems(for: leaf))
        }
        inlineItems = items
        inlineObjects.removeAll(keepingCapacity: true)
        inlineLinePlan = nil
        inlineContentRevision += 1
        inlineContentField.set(inlineContentRevision)
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

    private func makeItems(for leaf: DOMRef) -> [InlineItem] {
        var items: [InlineItem] = []
        if let text = leaf.text {
            addTextNode(text, into: &items)
        } else if let el = leaf.element {
            if el.tag == "br" {
                items.append(.lineBreak)
            } else {
                items.append(.embed(el))
            }
        }
        return items
    }

    private func collect(_ n: DOMRef, into items: inout [InlineItem]) {
        if let textNode = n.text {
            addTextNode(textNode, into: &items)
        } else if let el = n.element {
            if el.tag == "br" {
                items.append(.lineBreak)
            } else if el.tag == "input" || el.tag == "button" || el.tag == "img" || el.tag == "iframe" || el.tag == "canvas" {
                items.append(.embed(el))
            } else {
                for child in n.children { collect(child, into: &items) }
            }
        }
    }

    private func addTextNode(_ textNode: TextRef, into items: inout [InlineItem]) {
        textNode.ref.inheritedStyleOwner.style.field(.whiteSpace).touch(inlineContentField)
        let mode: WhiteSpaceMode = textNode.ref.inheritedStyleOwner.style.computed.text.whiteSpace
        let zoom: CGFloat = zoomField.read(notify: inlineContentField)
        let font: BrowserFont = fontForElement(textNode.ref, zoom: zoom, notify: inlineContentField)
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
                addSegment(text: segment, run: run, into: &items)
            }
        } else {
            addSegment(text: textNode.text, run: run, into: &items)
        }
    }

    private func addSegment(text: String, run: InlineTextRun, into items: inout [InlineItem]) {
        if run.whiteSpace.keepSpaces {
            if !text.isEmpty { addWord(text, run: run, into: &items) }
        } else {
            for word in text.split(whereSeparator: { $0.isWhitespace }) {
                addWord(String(word), run: run, into: &items)
            }
        }
    }

    private func addWord(_ word: String, run: InlineTextRun, into items: inout [InlineItem]) {
        profiler.count("text.words")

        if run.isAbbr && word.contains(where: { $0.isLowercase }) {
            addAbbrWord(run: run, word: word, into: &items)
            return
        }
        items.append(.text(InlineTextItem(run: run, word: word, display: nil)))
    }

    private func placeEmbed(_ element: ElementRef, index: Int, into placement: inout InlinePlacement) {
        placement.currentLine?.hasEmbed = true
        switch element.tag {
        case "input": addInput(element, index: index, into: &placement)
        case "button": addButton(element, index: index, into: &placement)
        case "img": addImage(element, index: index, into: &placement)
        case "iframe": addIframe(element, index: index, into: &placement)
        case "canvas": addCanvas(element, index: index, into: &placement)
        default: break
        }
    }

    private func placeText(_ item: InlineTextItem, index: Int?, into placement: inout InlinePlacement) {
        let font: BrowserFont = item.fontOverride ?? item.run.font
        let measured: CGFloat = item.measuredWidth ?? font.measure(item.display ?? item.word)
        let w: CGFloat = measured + font.spaceWidth
        if placement.cursorX + w > width && item.run.whiteSpace.wraps {
            if item.word.contains("\u{00AD}") {
                let parts: [String] = item.word.components(separatedBy: "\u{00AD}")
                var chunk: String = ""
                var breakIdx: Int = -1
                for (i, part) in parts.dropLast().enumerated() {
                    let candidate: String = chunk + part + "-"
                    if placement.cursorX + font.measure(candidate) <= width {
                        chunk = chunk + part
                        breakIdx = i
                    }
                }
                if breakIdx >= 0 {
                    appendToLine(clone(item, word: chunk + "-"), font: font, index: nil, into: &placement)
                    placement.endLine(parent: self)
                    placeText(
                        clone(item, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}")),
                        index: nil,
                        into: &placement
                    )
                    return
                }
            }
            placement.endLine(parent: self)
        }

        appendToLine(item, font: font, index: index, into: &placement)
        placement.cursorX += w
    }

    private func appendToLine(_ item: InlineTextItem, font: BrowserFont, index: Int?, into placement: inout InlinePlacement) {
        let line: LineLayout = placement.currentLine!
        let previous: (any LayoutObject)? = placement.children.last
        let text: TextLayout
        if let index,
            let cached = cachedText(at: index, node: item.run.node, word: item.word)
        {
            text = cached
            text.attach(to: line, previous: previous)
        } else {
            text = TextLayout(
                node: item.run.node,
                word: item.word,
                parent: line,
                previous: previous
            )
            text.font = font
            text.fontOverride = item.fontOverride
            text.displayWord = item.display
            text.whiteSpace = item.run.whiteSpace
            if let index {
                inlineObjects[index] = text
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

    private func addInput(_ node: ElementRef, index: Int, into placement: inout InlinePlacement) {
        if node.attributes["type"] == "hidden" { return }

        let available: CGFloat = widthField.get()
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: childrenField)
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : InputLayout.inputWidthPx * zoom
        if placement.cursorX + w > available { placement.endLine(parent: self) }
        let line: LineLayout = placement.currentLine!
        let prevItem: (any LayoutObject)? = placement.children.last
        let input: InputLayout
        if let cached = cachedEmbed(InputLayout.self, at: index, node: node) {
            input = cached
            input.attach(to: line, previous: prevItem)
        } else {
            input = InputLayout(node: node.ref, parent: line, previous: prevItem)
            inlineObjects[index] = input
        }
        placement.append(input)

        placement.cursorX += w + font.spaceWidth
    }

    private func addButton(_ node: ElementRef, index: Int, into placement: inout InlinePlacement) {
        let available: CGFloat = widthField.get()
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = InputLayout.inputWidthPx * zoom
        if placement.cursorX + w > available { placement.endLine(parent: self) }
        let line: LineLayout = placement.currentLine!
        let prevItem: (any LayoutObject)? = placement.children.last
        let button: ButtonLayout
        if let cached = cachedEmbed(ButtonLayout.self, at: index, node: node) {
            button = cached
            button.attach(to: line, previous: prevItem)
        } else {
            button = ButtonLayout(node: node.ref, parent: line, previous: prevItem)
            inlineObjects[index] = button
        }
        placement.append(button)
        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: childrenField)
        placement.cursorX += w + font.spaceWidth
    }

    private func addImage(_ node: ElementRef, index: Int, into placement: inout InlinePlacement) {
        let available: CGFloat = widthField.get()
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = ImageLayout.usedWidth(for: node, available: available, zoom: zoom, notify: childrenField)
        if placement.cursorX + w > available { placement.endLine(parent: self) }
        let line: LineLayout = placement.currentLine!
        let prevItem: (any LayoutObject)? = placement.children.last
        let image: ImageLayout
        if let cached = cachedEmbed(ImageLayout.self, at: index, node: node) {
            image = cached
            image.attach(to: line, previous: prevItem)
        } else {
            image = ImageLayout(node: node.ref, parent: line, previous: prevItem)
            inlineObjects[index] = image
        }
        placement.append(image)

        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: childrenField)
        placement.cursorX += w + font.spaceWidth
    }

    private func addIframe(_ node: ElementRef, index: Int, into placement: inout InlinePlacement) {
        let available: CGFloat = widthField.get()
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = IframeLayout.displaySize(for: node, notify: childrenField).width * zoom
        if placement.cursorX + w > available { placement.endLine(parent: self) }
        let line: LineLayout = placement.currentLine!
        let prevItem: (any LayoutObject)? = placement.children.last
        let iframe: IframeLayout
        if let cached = cachedEmbed(IframeLayout.self, at: index, node: node) {
            iframe = cached
            iframe.attach(to: line, previous: prevItem)
        } else {
            iframe = IframeLayout(node: node.ref, parent: line, previous: prevItem)
            inlineObjects[index] = iframe
        }
        placement.append(iframe)

        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: childrenField)
        placement.cursorX += w + font.spaceWidth
    }

    private func addCanvas(_ node: ElementRef, index: Int, into placement: inout InlinePlacement) {
        let available: CGFloat = widthField.get()
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = CanvasLayout.contentSize(for: node.raw).width * zoom
        if placement.cursorX + w > available { placement.endLine(parent: self) }
        let line: LineLayout = placement.currentLine!
        let prevItem: (any LayoutObject)? = placement.children.last
        let canvas: CanvasLayout
        if let cached = cachedEmbed(CanvasLayout.self, at: index, node: node) {
            canvas = cached
            canvas.attach(to: line, previous: prevItem)
        } else {
            canvas = CanvasLayout(node: node.ref, parent: line, previous: prevItem)
            inlineObjects[index] = canvas
        }
        placement.append(canvas)

        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: childrenField)
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

    private func addAbbrWord(run: InlineTextRun, word: String, into items: inout [InlineItem]) {
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
        owner.style.field(.fontWeight).touch(inlineContentField)
        owner.style.field(.fontStyle).touch(inlineContentField)
        owner.style.field(.fontSize).touch(inlineContentField)
        owner.style.field(.fontFamily).touch(inlineContentField)
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

    private func cachedText(at index: Int, node: DOMRef, word: String) -> TextLayout? {
        guard let text = inlineObjects[index] as? TextLayout,
            text.node.id == node.id,
            text.word == word
        else { return nil }
        return text
    }

    private func cachedEmbed<T: EmbedLayout>(
        _ type: T.Type,
        at index: Int,
        node: ElementRef
    ) -> T? {
        guard let embed = inlineObjects[index] as? T, embed.node.id == node.ref.id else { return nil }
        return embed
    }

    func selfRect() -> Rect {
        let top: CGFloat = paintedPadding(.paddingTop)
        let right: CGFloat = paintedPadding(.paddingRight)
        let bottom: CGFloat = paintedPadding(.paddingBottom)
        let left: CGFloat = paintedPadding(.paddingLeft)
        return Rect(
            left: x - left,
            top: y - top,
            right: x + width + right,
            bottom: y + height + bottom
        )
    }

    private func borderPaintRect() -> Rect {
        let rect: Rect = selfRect()
        let width: CGFloat = node.style.computed.box.decoration.border.width
        guard width > 0 else { return rect }
        let half: CGFloat = width / 2
        return Rect(
            left: rect.left - half,
            top: rect.top - half,
            right: rect.right + half,
            bottom: rect.bottom + half
        )
    }

    func paint(into items: inout [DisplayOp]) {
        let computed: ComputedStyle = node.style.computed
        let background: BrowserColor? = computed.visual.background.color
        if background != nil || computed.layout.overflow == .scroll {
            let radii: CornerRadii = computed.box.decoration.border.radii
            let color: BrowserColor = background ?? BrowserColor(
                red: 0, green: 0, blue: 0, alpha: 0
            )
            if !radii.isZero {
                items.append(.rrect(rect: selfRect(), radii: radii, color: color))
            } else {
                items.append(.rect(rect: selfRect(), color: color))
            }
        }

        if let el = node.element, let image = el.backgroundImage,
            computed.visual.background.image != nil {
            let box: Rect = selfRect()
            let dest: Rect = BackgroundSize(box: box, image: image, zoom: zoom)
                .rect(spec: computed.visual.background.size)
            items.append(.clippedImage(
                image: image,
                rendering: computed.visual.image.rendering,
                rect: dest,
                clip: box
            ))
        }

        if let border: DisplayOp = DisplayOp.fromBorderStyle(node, rect: borderPaintRect()) {
            items.append(border)
        }

        let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
        if node.isFocusVisible && outline == nil {
            let ring: (outer: String, inner: String) = focusRingColors(node)
            items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: ring.outer), width: 4))
            items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: ring.inner), width: 2))
        }
        if let outline = outline { items.append(outline) }

        if let el = node.element, el.tag == "li" {
            let bulletX: CGFloat = x - BlockLayout.liIndent
            let bulletY: CGFloat = y + (VSTEP - BlockLayout.bulletSize) / 2
            let bulletRect: Rect = Rect(
                left: bulletX, top: bulletY, right: bulletX + BlockLayout.bulletSize,
                bottom: bulletY + BlockLayout.bulletSize
            )
            items.append(.rect(rect: bulletRect, color: BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.canvasText : "black")))
        }
    }

    func paintCaret(into items: inout [DisplayOp]) {
        guard let el = node.element, el.isFocused,
            el.attributes["contenteditable"] != nil
        else { return }
        if let last = lastTextLayout() {
            items.append(drawCursor(last, offset: last.textWidth))
        } else {
            items.append(drawCursor(self, offset: 0))
        }
    }

    func paintScrollbar() -> [DisplayOp] {
        guard node.style.computed.layout.overflow == .scroll, contentHeight > height else { return [] }
        let barWidth: CGFloat = 8
        let ratio: CGFloat = height / contentHeight
        let barHeight: CGFloat = ratio * height
        let barTop: CGFloat = y + (scrollOffset / contentHeight) * height
        let barRect: Rect = Rect(
            left: x + width - barWidth, top: barTop, right: x + width, bottom: barTop + barHeight)
        return [.rect(rect: barRect, color: BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.canvasText : "gray"))]
    }

    func shouldPaint() -> Bool {
        if node.text != nil { return true }
        guard let el = node.element else { return true }
        return el.tag != "input" && el.tag != "button" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas"
    }

    func blockStyle() -> BlockStyle {
        let revision: UInt64 = node.style.revision
        if let cachedStyle, cachedStyleRevision == revision {
            profiler.count("layout.block.style.cache.hit")
            return cachedStyle
        }
        profiler.count("layout.block.style.cache.miss")
        let style: BlockStyle = BlockStyle(node: node)
        cachedStyle = style
        cachedStyleRevision = revision
        return style
    }

    // MARK: - Cursor

    private func lastTextLayout() -> TextLayout? {
        BlockLayout.lastTextLayout(in: self)
    }

    private static func lastTextLayout(in object: any LayoutObject) -> TextLayout? {
        for child in object.children.reversed() {
            if let text = child as? TextLayout { return text }
            if let nested = lastTextLayout(in: child) { return nested }
        }

        return nil
    }
}

// MARK: - Block child build

// Mutable cursor for one pass of the block child builder.
private struct BlockChildBuild {
    var built: [any LayoutObject] = []
    var previous: (any LayoutObject)?
    var inlineRun: [DOMRef] = []
    var pendingRunIn: ElementRef?
}

private enum BlockChildChange {
    case append([DOMRef])
    case insert([DOMRef], before: DOMRef)
}
