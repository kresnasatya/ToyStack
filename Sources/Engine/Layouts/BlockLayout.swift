import CoreGraphics

// MARK: - BlockLayout
@MainActor
class BlockLayout: LayoutObject {
    static let hiddenElements: Set<String> = ["head", "title", "script", "style"]

    static let liIndent: CGFloat = 20.0
    static let bulletSize: CGFloat = 8.0

    let node: any DOMNode
    var parent: (any LayoutObject)?
    private let previousField: ProtectedField<(any LayoutObject)?>
    var previous: (any LayoutObject)? {
        get { previousField.get() }
        set { setPrevious(newValue) }
    }
    private let childrenField: ProtectedField<[any LayoutObject]>
    var children: [any LayoutObject] {
        get { childrenField.get() }
        set { childrenField.set(newValue) }
    }
    var hasDirtyDescendants: Bool = false
    private var childChanges: [BlockChildChange] = []
    let extraNodes: [any DOMNode]
    let xField: ProtectedField<CGFloat>
    var x: CGFloat {
        get { xField.get() }
        set { xField.set(newValue) }
    }
    let yField: ProtectedField<CGFloat>
    var y: CGFloat {
        get { yField.get() }
        set { yField.set(newValue) }
    }
    let widthField: ProtectedField<CGFloat>
    var width: CGFloat {
        get { widthField.get() }
        set { widthField.set(newValue) }
    }
    let heightField: ProtectedField<CGFloat>
    var height: CGFloat {
        get { heightField.get() }
        set { heightField.set(newValue) }
    }
    let zoomField: ProtectedField<CGFloat>
    var zoom: CGFloat {
        get { zoomField.get() }
        set { zoomField.set(newValue) }
    }
    var paintCache: PaintCache = PaintCache()

    private var cursorX: CGFloat = 0
    private var inlineItems: [InlineItem] = []

    var scrollOffset: CGFloat = 0
    var contentHeight: CGFloat = 0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.childrenField = ProtectedField(
            owner: FieldOwner(name: "children", node: node, parent: parent),
            equals: { lhs, rhs in
                guard lhs.count == rhs.count else { return false }
                return zip(lhs, rhs).allSatisfy({ pair in pair.0 === pair.1 })
            }
        )
        self.widthField = ProtectedField("width", node: node, parent: parent)
        self.heightField = ProtectedField("height", node: node, parent: parent)
        self.xField = ProtectedField("x", node: node, parent: parent)
        self.yField = ProtectedField("y", node: node, parent: parent)
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.previousField = ProtectedField(
            owner: FieldOwner(name: "previous", node: node, parent: parent), equals: { (lhs: (any LayoutObject)?, rhs: (any LayoutObject)?) -> Bool in
                lhs === rhs
            },
            cleanValue: previous
        )
        self.node = node
        self.extraNodes = []
        self.parent = parent
        node.layoutObject = self
        previousField.setDependencies([])
        freezeGeometry(parent: parent, previous: previous)
    }

    init(nodes: [any DOMNode], parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.childrenField = ProtectedField(
            owner: FieldOwner(name: "children", node: nodes[0], parent: parent),
            equals: { lhs, rhs in
                guard lhs.count == rhs.count else { return false }
                return zip(lhs, rhs).allSatisfy({ pair in pair.0 === pair.1 })
            }
        )
        self.widthField = ProtectedField("width", node: nodes[0], parent: parent)
        self.heightField = ProtectedField("height", node: nodes[0], parent: parent)
        self.xField = ProtectedField("x", node: nodes[0], parent: parent)
        self.yField = ProtectedField("y", node: nodes[0], parent: parent)
        self.zoomField = ProtectedField("zoom", node: nodes[0], parent: parent)
        self.previousField = ProtectedField(
            owner: FieldOwner(name: "previous", node: nodes[0], parent: parent), equals: { (lhs: (any LayoutObject)?, rhs: (any LayoutObject)?) -> Bool in
                lhs === rhs
            },
            cleanValue: previous
        )
        self.node = nodes[0]
        self.extraNodes = nodes
        self.parent = parent
        previousField.setDependencies([])
        freezeGeometry(parent: parent, previous: previous)
    }

    private func freezeGeometry(parent: any LayoutObject, previous: (any LayoutObject)?) {
        zoomField.setDependencies([parent.zoomField, node.style.field("zoom")])
        xField.setDependencies([
            parent.xField,
            zoomField,
            node.style.field("padding-left"),
            node.style.field("position"),
            node.style.field("left"),
        ])
        var yInputs: [any InvalidatableField] = [
            parent.yField,
            previousField,
            zoomField,
            node.style.field("padding-top"),
            node.style.field("top"),
            node.style.field("margin-top"),
        ]
        if let previous {
            yInputs.append(previous.yField)
            yInputs.append(previous.heightField)
            yInputs.append(previous.node.style.field("margin-bottom"))
            yInputs.append(previous.node.style.field("padding-bottom"))
        }
        yField.setDependencies(yInputs)
        widthField.setDependencies([
            parent.widthField,
            zoomField,
            node.style.field("padding-left"),
            node.style.field("padding-right"),
            node.style.field("width"),
        ])
        childrenField.setDependencies(childrenInputs())
    }

    private func childrenInputs() -> [any InvalidatableField] {
        var inputs: [any InvalidatableField] = [
            zoomField,
            node.style.field("display"),
            node.style.field("position"),
            node.style.field("direction"),
        ]
        if extraNodes.isEmpty {
            for child in node.children {
                inputs.append(child.style.field("display"))
                inputs.append(child.style.field("position"))
            }
        }
        // A block-only container's child list does not depend on its width.
        // Width only matters when this block lays out lines or anonymous runs;
        // their own width fields carry the dependency.
        let hasBlockChild: Bool = node.children.contains(where: { $0.style["display"] == "block" })
        if !hasBlockChild {
            inputs.append(widthField)
        }
        let leaves: [any DOMNode] = inlineLeaves()
        for leaf in leaves {
            let owner: any DOMNode = leaf.inheritedStyleOwner
            inputs.append(owner.style.field("white-space"))
            inputs.append(contentsOf: fontInputs(for: leaf))
            if let el = leaf as? Element {
                inputs.append(el.style.field("aspect-ratio"))
                inputs.append(el.style.field("max-width"))
            }
        }
        return inputs
    }

    // Only leaves this block lays out inline. Nested blocks own their own inputs.
    private func inlineLeaves() -> [any DOMNode] {
        var leaves: [any DOMNode] = []
        if !extraNodes.isEmpty {
            for n in extraNodes { collectLeaves(n, into: &leaves) }
            return leaves
        }
        let hasBlockChild: Bool = node.children.contains(where: {
            $0.style["display"] == "block"
        })
        if !hasBlockChild {
            collectLeaves(node, into: &leaves)
            return leaves
        }
        for child in node.children where child.style["display"] != "block" {
            collectLeaves(child, into: &leaves)
        }
        return leaves
    }

    private func setHeightInputs() {
        var inputs: [any InvalidatableField] = [
            childrenField,
            zoomField,
            node.style.field("height"),
        ]
        for child in children {
            inputs.append(child.heightField)
            inputs.append(child.node.style.field("position"))
            inputs.append(child.node.style.field("margin-top"))
            inputs.append(child.node.style.field("margin-bottom"))
            if child is BlockLayout {
                inputs.append(child.node.style.field("padding-top"))
                inputs.append(child.node.style.field("padding-bottom"))
            }
        }
        heightField.setDependencies(inputs)
    }

    func markChildrenDirty() {
        childChanges.removeAll()
        childrenField.mark()
    }

    func noteAppendedChildren(_ nodes: [any DOMNode]) {
        childChanges.append(.append(nodes))
        markAncestorsDirty()
    }

    func noteInsertedChildren(_ nodes: [any DOMNode], before reference: any DOMNode) {
        childChanges.append(.insert(nodes, before: reference))
        markAncestorsDirty()
    }

    private func setPrevious(_ newValue: (any LayoutObject)?) {
        guard previous !== newValue else { return }
        previousField.set(newValue)
        guard let newValue else { return }
        yField.setDependencies([
            newValue.yField,
            newValue.heightField,
            newValue.node.style.field("margin-bottom"),
            newValue.node.style.field("padding-bottom"),
        ])
    }

    private func markAncestorsDirty() {
        var current: (any LayoutObject)? = parent
        while let object = current, !object.hasDirtyDescendants {
            object.hasDirtyDescendants = true
            current = object.parent
        }
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        if zoomField.dirty || xField.dirty || yField.dirty
            || widthField.dirty || heightField.dirty
        {
            return true
        }

        return childrenField.dirty || !childChanges.isEmpty
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
        if childrenField.dirty || !childChanges.isEmpty {
            childrenField.setDependencies(childrenInputs())
        }
        profiler.measure("layout.visit") {
            profiler.count("layout.rebuilt")
            zoom = resolvedZoom()
            let isAbsolute: Bool = node.style.read("position", notify: xField) == "absolute"

            let parentX: CGFloat = parent!.xField.read(notify: xField)
            let padLeft: CGFloat = padding("left", notify: xField)
            if isAbsolute,
                let lStr = node.style.read("left", notify: xField),
                lStr.hasSuffix("px"),
                let l = Double(lStr.dropLast(2))
            {
                let absoluteXZoom: CGFloat = zoomField.read(notify: xField)
                xField.set(CGFloat(l) * absoluteXZoom + padLeft)
            } else {
                xField.set(parentX + padLeft)
            }

            let parentWidth: CGFloat = parent!.widthField.read(notify: widthField)
            let zoom: CGFloat = zoomField.read(notify: widthField)
            let padHorizontal: CGFloat = padding("left", notify: widthField) + padding("right", notify: widthField)
            if let wStr = node.style.read("width", notify: widthField),
                wStr.hasSuffix("px"),
                let w = Double(wStr.dropLast(2))
            {
                widthField.set(CGFloat(w) * zoom)
            } else {
                widthField.set(max(0, parentWidth - padHorizontal))
            }

            if let el = node as? Element, el.tag == "li" {
                x += BlockLayout.liIndent
                width -= BlockLayout.liIndent
            }

            if isAbsolute, let tStr = node.style.read("top", notify: yField),
                tStr.hasSuffix("px"),
                let t = Double(tStr.dropLast(2))
            {
                let absoluteYZoom: CGFloat = zoomField.read(notify: yField)
                yField.set(CGFloat(t) * absoluteYZoom + padding("top", notify: yField))
            } else {
                let ownTop: CGFloat = marginPx(node, "margin-top", notify: yField)
                let padTop: CGFloat = padding("top", notify: yField)
                if let prev = previous {
                    let prevY: CGFloat = prev.yField.read(notify: yField)
                    let prevHeight: CGFloat = prev.heightField.read(notify: yField)
                    let prevPadBottom: CGFloat = (prev as? BlockLayout)?.padding("bottom", notify: yField) ?? 0
                    yField.set(
                        prevY + prevHeight + prevPadBottom
                            + marginPx(prev.node, "margin-bottom", notify: yField)
                            + ownTop + padTop
                    )
                } else {
                    yField.copy(from: parent!.yField)
                    yField.set(yField.get() + ownTop + padTop)
                }
            }

            if let el = node as? Element, el.attributes["id"] == "toc" {
                y += VSTEP
            }

            let mode: String = profiler.measure("layout.mode", { layoutMode() })
            if mode == "block" {
                profiler.count("layout.mode.block")
                if childrenField.dirty {
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
            } else {
                profiler.count("layout.mode.inline")
                childChanges.removeAll()
                // Inline layout consumes these inputs but has no field of its own;
                // route them to the child list that would have to be rebuilt.
                _ = widthField.read(notify: childrenField)
                _ = zoomField.read(notify: childrenField)
                _ = node.style.read("direction", notify: childrenField)
                profiler.measure("layout.inline.refresh", { refreshInlineItems() })
                profiler.measure("layout.inline.place", { placeInlineItems() })
            }
        }

        for child in children { child.layout() }

        setHeightInputs()
        let heightChildren: [any LayoutObject] = childrenField.read(notify: heightField)
        let sumHeight: Double = profiler.measure("layout.height", {
            heightChildren.reduce(0) { total, child in
                let position: String = child.node.style.read("position", notify: heightField) ?? "static"
                if position == "absolute" { return total }
                var h: CGFloat = child.heightField.read(notify: heightField)
                if let block = child as? BlockLayout {
                    h += block.paddingVertical(notify: heightField)
                    h += marginPx(child.node, "margin-top", notify: heightField)
                    h += marginPx(child.node, "margin-bottom", notify: heightField)
                }
                return total + h
            }
        })

        if let hStr = node.style.read("height", notify: heightField),
            hStr.hasSuffix("px"),
            let h = Double(hStr.dropLast(2))
        {
            contentHeight = sumHeight
            let styleHeightZoom: CGFloat = zoomField.read(notify: heightField)
            heightField.set(CGFloat(h) * styleHeightZoom)
        } else {
            contentHeight = sumHeight
            heightField.set(sumHeight)
        }

        if let el = node as? Element, el.attributes["id"] == "toc" {
            height += VSTEP
        }

        if let el = node as? Element, el.style["overflow"] == "scroll" {
            let maxScroll: CGFloat = max(0, contentHeight - height)
            scrollOffset = min(el.scrollOffsetY, maxScroll)
        }
    }

    private func layoutMode() -> String {
        if !extraNodes.isEmpty { return "inline" }
        if node is TextNode { return "inline" }
        let hasBlockChild: Bool = node.children.contains(where: {
            $0.style.read("display", notify: childrenField) == "block"
        })
        if hasBlockChild { return "block" }
        if let el = node as? Element {
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

    private func appendBlockChildren(_ nodes: [any DOMNode], to current: [any LayoutObject]) -> [any LayoutObject]? {
        guard extraNodes.isEmpty, current.allSatisfy({ $0 is BlockLayout }) else {
            return nil
        }
        if let last: BlockLayout = current.last as? BlockLayout,
            last.extraNodes.isEmpty,
            (last.node as? Element)?.tag == "h6"
        {
            return nil
        }
        guard let first: any DOMNode = firstVisibleChild(in: nodes) else {
            return nil
        }

        var state: BlockChildBuild = BlockChildBuild(
            built: current,
            previous: lastFlowChild(in: current)
        )
        let startsInline: Bool = first.style.read("display", notify: childrenField) != "block"
        if startsInline,
            let last: BlockLayout = state.built.last as? BlockLayout,
            !last.extraNodes.isEmpty,
            last.extraNodes.allSatisfy({ $0.style.read("display", notify: childrenField ) != "block" })
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
        _ nodes: [any DOMNode],
        before reference: any DOMNode,
        in current: [any LayoutObject]
    ) -> [any LayoutObject]? {
        guard extraNodes.isEmpty, current.allSatisfy({ $0 is BlockLayout }) else {
            return nil
        }
        guard let index: Int = blockChildIndex(of: reference, in: current) else {
            return nil
        }
        guard !nodes.contains(where: { ($0 as? Element)?.tag == "h6" }) else {
            return nil
        }
        if index > 0, let previous = current[index - 1] as? BlockLayout, isRunIn(previous) {
            return nil
        }
        if let referenceBlock = current[index] as? BlockLayout, isRunIn(referenceBlock) {
            return nil
        }
        guard let first: any DOMNode = firstVisibleChild(in: nodes) else {
            return current
        }

        let startsInline: Bool = first.style.read("display", notify: childrenField) != "block"
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
                || block.node.style.read("position", notify: childrenField) != "absolute"
            if isFlow { previous = block }
        }

        var result: [any LayoutObject] = state.built
        result.append(contentsOf: current[index...])
        return result
    }

    private func blockChildIndex(
        of reference: any DOMNode,
        in current: [any LayoutObject]
    ) -> Int? {
        for (index, object) in current.enumerated() {
            guard let block = object as? BlockLayout else { return nil }
            if block.node === reference, block.extraNodes.isEmpty {
                return index
            }
            if block.extraNodes.contains(where: { $0 === reference }) {
                return nil
            }
        }
        return nil
    }

    private func isRunIn(_ block: BlockLayout) -> Bool {
        let first: (any DOMNode)? = block.extraNodes.first ?? block.node
        return (first as? Element)?.tag == "h6"
    }

    private func firstVisibleChild(in nodes: [any DOMNode]) -> (any DOMNode)? {
        return nodes.first(where: { child in
            guard let el = child as? Element else { return true }
            return !BlockLayout.hiddenElements.contains(el.tag)
        })
    }

    private func lastFlowChild(in children: [any LayoutObject]) -> (any LayoutObject)? {
        for child in children.reversed() {
            if let block = child as? BlockLayout, !block.extraNodes.isEmpty {
                return child
            }
            if child.node.style.read("position", notify: childrenField) != "absolute" {
                return child
            }
        }
        return nil
    }

    private func consumeBlockChildren(_ nodes: [any DOMNode], state: inout BlockChildBuild) {
        for child in nodes {
            if let el = child as? Element, BlockLayout.hiddenElements.contains(el.tag) {
                continue
            }
            let isBlock: Bool = child.style.read("display", notify: childrenField) == "block"
            if isBlock {
                if let el = child as? Element, el.tag == "h6" {
                    flushInlineRun(into: &state)
                    state.pendingRunIn = el
                } else {
                    flushInlineRun(into: &state)
                    if let runIn = state.pendingRunIn {
                        let run: [any DOMNode] = [runIn, child]
                        let next: BlockLayout = BlockLayout(nodes: run, parent: self, previous: state.previous)
                        state.built.append(next)
                        state.previous = next
                        state.pendingRunIn = nil
                    } else {
                        let next: BlockLayout = BlockLayout(node: child, parent: self, previous: state.previous)
                        state.built.append(next)
                        if child.style.read("position", notify: childrenField) != "absolute" {
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
        let run: [any DOMNode] = state.inlineRun
        let anon: BlockLayout = BlockLayout(nodes: run, parent: self, previous: state.previous)
        state.built.append(anon)
        state.previous = anon
        state.inlineRun = []
    }

    private func finishBlockChildren(_ state: inout BlockChildBuild) {
        flushInlineRun(into: &state)
        if let runIn = state.pendingRunIn {
            let next: BlockLayout = BlockLayout(node: runIn, parent: self, previous: state.previous)
            state.built.append(next)
        }
    }

    private func marginPx(_ n: any DOMNode, _ prop: String, notify: any InvalidatableField) -> CGFloat {
        guard let s = n.style.read(prop, notify: notify), s.hasSuffix("px"), let v = Double(s.dropLast(2)) else { return 0 }
        return scaled(CGFloat(v))
    }

    // MARK: - Padding

    private func padding(_ side: String, notify: any InvalidatableField) -> CGFloat {
        guard extraNodes.isEmpty else { return 0 }
        guard let raw: String = node.style.read("padding-\(side)", notify: notify),
            raw.hasSuffix("px"),
            let value: Double = Double(raw.dropLast(2))
        else { return 0 }
        return scaled(CGFloat(max(0, value)))
    }

    private func paintedPadding(_ side: String) -> CGFloat {
        guard extraNodes.isEmpty else { return 0 }
        guard let raw: String = node.style["padding-\(side)"],
            raw.hasSuffix("px"),
            let value: Double = Double(raw.dropLast(2))
        else { return 0 }
        return scaled(CGFloat(max(0, value)))
    }

    func paddingVertical(notify: any InvalidatableField) -> CGFloat {
        padding("top", notify: notify) + padding("bottom", notify: notify)
    }

    func boxHeight(notify: any InvalidatableField) -> CGFloat {
        heightField.read(notify: notify) + paddingVertical(notify: notify)
    }

    // MARK: - Inline items
    private func buildInlineItems() -> [InlineItem] {
        var items: [InlineItem] = []
        if extraNodes.isEmpty {
            collect(node, into: &items)
        } else {
            for n in extraNodes { collect(n, into: &items) }
        }
        return items
    }

    private func placeInlineItems() {

        children = []
        newLine()
        for item in inlineItems {
            switch item {
            case .lineBreak:
                newLine()
            case .text(let text):
                placeText(text)
            case .embed(let element):
                placeEmbed(element)
            }
        }

        profiler.count("layout.lines.total", by: children.count)
    }

    private func refreshInlineItems() {
        let leaves: [any DOMNode] = inlineLeaves()
        var items: [InlineItem] = []
        for leaf in leaves {
            items.append(contentsOf: makeItems(for: leaf))
        }
        inlineItems = items
    }

    private func collectLeaves(_ n: any DOMNode, into leaves: inout [any DOMNode]) {
        if n is TextNode {
            leaves.append(n)
            return
        }
        guard let el = n as? Element else { return }
        if el.tag == "br" || isEmbed(el) {
            leaves.append(el)
            return
        }
        for child in el.children { collectLeaves(child, into: &leaves) }
    }

    private func isEmbed(_ el: Element) -> Bool {
        el.tag == "input" || el.tag == "button" || el.tag == "img"
        || el.tag == "iframe" || el.tag == "canvas"
    }

    private func makeItems(for leaf: any DOMNode) -> [InlineItem] {
        var items: [InlineItem] = []
        if let text = leaf as? TextNode {
            addTextNode(text, into: &items)
        } else if let el = leaf as? Element {
            if el.tag == "br" {
                items.append(.lineBreak)
            } else {
                items.append(.embed(el))
            }
        }
        return items
    }

    private func collect(_ n: any DOMNode, into items: inout [InlineItem]) {
        if let textNode = n as? TextNode {
            addTextNode(textNode, into: &items)
        } else if let el = n as? Element {
            if el.tag == "br" {
                items.append(.lineBreak)
            } else if el.tag == "input" || el.tag == "button" || el.tag == "img" || el.tag == "iframe" || el.tag == "canvas" {
                items.append(.embed(el))
            } else {
                for child in el.children { collect(child, into: &items) }
            }
        }
    }

    private func addTextNode(_ textNode: TextNode, into items: inout [InlineItem]) {
        let mode: WhiteSpaceMode = WhiteSpaceMode(cssValue: textNode.inheritedStyleOwner.style.read("white-space", notify: childrenField))
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let font: BrowserFont = fontForElement(textNode, zoom: zoom, notify: childrenField)
        let run: InlineTextRun = InlineTextRun(
            node: textNode,
            font: font,
            whiteSpace: mode,
            isAbbr: isInsideAbbr(textNode),
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

    private func placeEmbed(_ element: Element) {
        if let line = children.last as? LineLayout { line.hasEmbed = true }
        switch element.tag {
        case "input": addInput(element)
        case "button": addButton(element)
        case "img": addImage(element)
        case "iframe": addIframe(element)
        case "canvas": addCanvas(element)
        default: break
        }
    }

    private func placeText(_ item: InlineTextItem) {
        let font: BrowserFont = item.fontOverride ?? item.run.font
        let measured: CGFloat = font.measure(item.display ?? item.word)
        let w: CGFloat = measured + font.spaceWidth
        if cursorX + w > width && item.run.whiteSpace.wraps {
            if item.word.contains("\u{00AD}") {
                let parts: [String] = item.word.components(separatedBy: "\u{00AD}")
                var chunk: String = ""
                var breakIdx: Int = -1
                for (i, part) in parts.dropLast().enumerated() {
                    let candidate: String = chunk + part + "-"
                    if cursorX + font.measure(candidate) <= width {
                        chunk = chunk + part
                        breakIdx = i
                    }
                }
                if breakIdx >= 0 {
                    appendToLine(clone(item, word: chunk + "-"), font: font)
                    newLine()
                    placeText(clone(item, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}")))
                    return
                }
            }
            newLine()
        }

        appendToLine(item, font: font)
        cursorX += w
    }

    private func appendToLine(_ item: InlineTextItem, font: BrowserFont) {
        let line: LineLayout = children.last as! LineLayout
        let text: TextLayout = TextLayout(
            node: item.run.node,
            word: item.word,
            parent: line,
            previous: line.children.last
        )
        text.font = font
        text.fontOverride = item.fontOverride
        text.displayWord = item.display
        text.whiteSpace = item.run.whiteSpace
        line.children.append(text)
    }

    private func clone(_ item: InlineTextItem, word: String) -> InlineTextItem {
        InlineTextItem(
            run: item.run,
            word: word,
            display: nil,
            fontOverride: item.fontOverride
        )
    }

    private func newLine() {
        cursorX = 0
        let lastLine: (any LayoutObject)? = children.last
        let line: LineLayout = LineLayout(node: node, parent: self, previous: lastLine)
        children.append(line)
    }

    private func addInput(_ node: Element) {
        if node.attributes["type"] == "hidden" { return }

        let available: CGFloat = widthField.read(notify: childrenField)
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let font: BrowserFont = fontForElement(node, zoom: zoom, notify: childrenField)
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : InputLayout.inputWidthPx * zoom
        if cursorX + w > available { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let input: InputLayout = InputLayout(node: node, parent: line, previous: prevItem)
        line.children.append(input)

        cursorX += w + font.spaceWidth
    }

    private func addButton(_ node: Element) {
        let available: CGFloat = widthField.read(notify: childrenField)
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = InputLayout.inputWidthPx * zoom
        if cursorX + w > available { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let button: ButtonLayout = ButtonLayout(node: node, parent: line, previous: prevItem)
        line.children.append(button)
        let font: BrowserFont = fontForElement(node, zoom: zoom, notify: childrenField)
        cursorX += w + font.spaceWidth
    }

    private func addImage(_ node: Element) {
        let available: CGFloat = widthField.read(notify: childrenField)
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = ImageLayout.usedWidth(for: node, available: available, zoom: zoom, notify: childrenField)
        if cursorX + w > available { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let image: ImageLayout = ImageLayout(node: node, parent: line, previous: prevItem)
        line.children.append(image)

        let font: BrowserFont = fontForElement(node, zoom: zoom, notify: childrenField)
        cursorX += w + font.spaceWidth
    }

    private func addIframe(_ node: Element) {
        let available: CGFloat = widthField.read(notify: childrenField)
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = IframeLayout.displaySize(for: node, notify: childrenField).width * zoom
        if cursorX + w > available { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let iframe: IframeLayout = IframeLayout(node: node, parent: line, previous: prevItem)
        line.children.append(iframe)

        let font: BrowserFont = fontForElement(node, zoom: zoom, notify: childrenField)
        cursorX += w + font.spaceWidth
    }

    private func addCanvas(_ node: Element) {
        let available: CGFloat = widthField.read(notify: childrenField)
        let zoom: CGFloat = zoomField.read(notify: childrenField)
        let w: CGFloat = CanvasLayout.contentSize(for: node).width * zoom
        if cursorX + w > available { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let canvas: CanvasLayout = CanvasLayout(node: node, parent: line, previous: prevItem)
        line.children.append(canvas)

        let font: BrowserFont = fontForElement(node, zoom: zoom, notify: childrenField)
        cursorX += w + font.spaceWidth
    }

    private func isInsideAbbr(_ node: any DOMNode) -> Bool {
        var current: (any DOMNode)? = node.parent
        while let c = current {
            if let el = c as? Element, el.tag == "abbr" { return true }
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

        let node: any DOMNode = run.node
        let owner: any DOMNode = node.inheritedStyleOwner
        let weight: String = owner.style.read("font-weight", notify: childrenField) ?? "normal"
        var styleStr: String = owner.style.read("font-style", notify: childrenField) ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx: Double = Double(owner.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt: Int = Int(sizePx)
        let smallSize: Int = Int(Double(sizeInt))
        let family: String = owner.style.read("font-family", notify: childrenField) ?? "serif"

        for (text, isLower) in runs {
            let displayText: String = isLower ? text.uppercased() : text
            let font: BrowserFont =
                isLower
                ? getFont(size: smallSize, weight: "bold", style: styleStr, family: family)
                : getFont(size: sizeInt, weight: weight, style: styleStr, family: family)
            items.append(.text(InlineTextItem(run: run, word: text, display: displayText, fontOverride: font)))
        }
    }

    func selfRect() -> Rect {
        let top: CGFloat = paintedPadding("top")
        let right: CGFloat = paintedPadding("right")
        let bottom: CGFloat = paintedPadding("bottom")
        let left: CGFloat = paintedPadding("left")
        return Rect(
            left: x - left,
            top: y - top,
            right: x + width + right,
            bottom: y + height + bottom
        )
    }

    private func borderPaintRect() -> Rect {
        let rect: Rect = selfRect()
        guard let width: CGFloat = CSSValueParser.outlineWidth(node.style["border-width"] ?? "medium"),
            width > 0
        else { return rect }
        let half: CGFloat = width / 2
        return Rect(
            left: rect.left - half,
            top: rect.top - half,
            right: rect.right + half,
            bottom: rect.bottom + half
        )
    }

    func paint(into items: inout [any DisplayItem]) {
        let bgcolor: String = node.style["background-color"] ?? "transparent"
        if bgcolor != "transparent" || node.style["overflow"] == "scroll" {
            let radii: CornerRadii = CSSValueParser.cornerRadii(node.style) ?? .zero
            if !radii.isZero {
                items.append(
                    DrawRRect(
                        rect: selfRect(),
                        parentEffect: nil,
                        radii: radii,
                        color: bgcolor
                    )
                )
            } else {
                items.append(DrawRect(rect: selfRect(), color: bgcolor))
            }
        }

        if let el = node as? Element, let image = el.backgroundImage,
            let value = node.style["background-image"], value != "none" {
            let box: Rect = selfRect()
            let dest: Rect = BackgroundSize(box: box, image: image, zoom: zoom).rect(css: node.style["background-size"])
            items.append(DrawClippedImage(image: image, rendering: ImageRendering(css: node.style["image-rendering"]), rect: dest, clip: box))
        }

        if let border: DrawOutline = DrawOutline.fromBorderStyle(node, rect: borderPaintRect()) {
            items.append(border)
        }

        let outline: DrawOutline? = DrawOutline.fromStyle(node, rect: selfRect())
        if node.isFocusVisible && outline == nil {
            let ring: (outer: String, inner: String) = focusRingColors(node)
            items.append(DrawOutline(rect: selfRect(), color: ring.outer, thickness: 4))
            items.append(DrawOutline(rect: selfRect(), color: ring.inner, thickness: 2))
        }
        if let outline = outline { items.append(outline) }

        if let el = node as? Element, el.tag == "li" {
            let bulletX: CGFloat = x - BlockLayout.liIndent
            let bulletY: CGFloat = y + (VSTEP - BlockLayout.bulletSize) / 2
            let bulletRect: Rect = Rect(
                left: bulletX, top: bulletY, right: bulletX + BlockLayout.bulletSize,
                bottom: bulletY + BlockLayout.bulletSize
            )
            items.append(DrawRect(rect: bulletRect, color: usesForcedColors(node) ? ForcedColor.canvasText : "black"))
        }

        if let el = node as? Element, el.attributes["id"] == "toc" {
            let headerRect: Rect = Rect(left: x, top: y - VSTEP, right: x + width, bottom: y)
            items.append(DrawRect(rect: headerRect, color: usesForcedColors(node) ? ForcedColor.canvasText : "gray"))
            let font: BrowserFont = getFont(size: 12, weight: "bold", style: "roman")
            items.append(
                DrawText(
                    at: Point(x: x, y: y),
                    text: "Table of Contents",
                    font: font,
                    color: usesForcedColors(node) ? ForcedColor.canvas : "white"
                )
            )
        }
    }

    func paintEffects(into items: inout [any DisplayItem], from start: Int) {
        if let el = node as? Element, el.isFocused,
            el.attributes["contenteditable"] != nil
        {
            if let last = lastTextLayout() {
                items.append(drawCursor(last, offset: last.textWidth))
            } else {
                items.append(drawCursor(self, offset: 0))
            }
        }
        applyPaintEffects(into: &items, from: start)
    }

    func paintScrollbar() -> [any DisplayItem] {
        guard node.style["overflow"] == "scroll", contentHeight > height else { return [] }
        let barWidth: CGFloat = 8
        let ratio: CGFloat = height / contentHeight
        let barHeight: CGFloat = ratio * height
        let barTop: CGFloat = y + (scrollOffset / contentHeight) * height
        let barRect: Rect = Rect(
            left: x + width - barWidth, top: barTop, right: x + width, bottom: barTop + barHeight)
        return [DrawRect(rect: barRect, color: usesForcedColors(node) ? ForcedColor.canvasText : "gray")]
    }

    func shouldPaint() -> Bool {
        if node is TextNode { return true }
        guard let el = node as? Element else { return true }
        return el.tag != "input" && el.tag != "button" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas"
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
    var inlineRun: [any DOMNode] = []
    var pendingRunIn: Element?
}

private enum BlockChildChange {
    case append([any DOMNode])
    case insert([any DOMNode], before: any DOMNode)
}
