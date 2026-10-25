import CoreGraphics

// MARK: - BlockLayout
@MainActor
class BlockLayout: LayoutObject {
    static let hiddenElements: Set<String> = ["head", "title", "script", "style"]

    static let inputWidthPx: CGFloat = 200
    static let liIndent: CGFloat = 20.0
    static let bulletSize: CGFloat = 8.0

    let node: any DOMNode
    var parent: (any LayoutObject)?
    var previous: (any LayoutObject)?
    private let childrenField: ProtectedField<[any LayoutObject]>
    var children: [any LayoutObject] {
        get { childrenField.get() }
        set { childrenField.set(newValue) }
    }
    var hasDirtyDescendants: Bool = false
    let extraNodes: [any DOMNode]
    var x: CGFloat = 0
    var y: CGFloat = 0
    let widthField: ProtectedField<CGFloat>
    var width: CGFloat {
        get { widthField.get() }
        set { widthField.set(newValue) }
    }
    var height: CGFloat = 0
    let zoomField: ProtectedField<CGFloat>
    var zoom: CGFloat {
        get { zoomField.get() }
        set { zoomField.set(newValue) }
    }
    var paintCache: PaintCache = PaintCache()

    private var cursorX: CGFloat = 0
    private var fontByNode: [ObjectIdentifier: BrowserFont] = [:]
    private var inlineItems: [InlineItem] = []
    private var itemsByNode: [ObjectIdentifier: [InlineItem]] = [:]
    private var inlineBuilt: Bool = false
    private var usedWidth: CGFloat = -1

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
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.node = node
        self.extraNodes = []
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
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
        self.zoomField = ProtectedField("zoom", node: nodes[0], parent: parent)
        self.node = nodes[0]
        self.extraNodes = nodes
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        layout(reusesChildren: false)
    }

    func markChildrenDirty() {
        childrenField.mark()
    }

    func layout(reusesChildren: Bool) {
        var skippedChildren: Bool = false
        let stale: Bool = subtreeStale
        profiler.measure("layout.visit") {
            zoom = resolvedZoom()
            let isAbsolute: Bool = node.style["position"] == "absolute"
            let oldX: CGFloat = x
            let oldY: CGFloat = y
            if isAbsolute, let lStr = node.style["left"], lStr.hasSuffix("px"),
                let l = Double(lStr.dropLast(2))
            {
                x = scaled(CGFloat(l))
            } else {
                x = parent!.x
            }

            let parentWidth: CGFloat = parent!.widthField.read(notify: widthField)
            let zoom: CGFloat = zoomField.read(notify: widthField)
            if let wStr = node.style["width"], wStr.hasSuffix("px"), let w = Double(wStr.dropLast(2)) {
                widthField.set(CGFloat(w) * zoom)
            } else {
                widthField.set(parentWidth)
            }

            if let el = node as? Element, el.tag == "li" {
                x += BlockLayout.liIndent
                width -= BlockLayout.liIndent
            }

            if isAbsolute, let tStr = node.style["top"], tStr.hasSuffix("px"),
                let t = Double(tStr.dropLast(2))
            {
                y = scaled(CGFloat(t))
            } else {
                let ownTop: CGFloat = marginPx(node, "margin-top")
                if let prev = previous, prev is BlockLayout {
                    y = prev.y + prev.height + marginPx(prev.node, "margin-bottom") + ownTop
                } else {
                    y = (previous.map { $0.y + $0.height } ?? parent!.y) + ownTop
                }
            }

            if let el = node as? Element, el.attributes["id"] == "toc" {
                y += VSTEP
            }

            if reusesChildren, usedWidth == width, !stale, !childrenField.dirty {
                skippedChildren = true
                profiler.count("layout.reusedChildren")
                let dx: CGFloat = x - oldX
                let dy: CGFloat = y - oldY
                for child in childrenField.get() { translateSubtree(child, dx: dx, dy: dy) }
                return
            }
            profiler.count("layout.rebuilt")
            if !reusesChildren { profiler.count("layout.rebuildReason.noReuse") }
            if usedWidth != width { profiler.count("layout.rebuildReason.widthChanged") }
            if stale { profiler.count("layout.rebuildReason.dirtyFlag") }

            usedWidth = width
            let mode: String = profiler.measure("layout.mode", { layoutMode() })
            if mode == "block" {
                profiler.count("layout.mode.block")
                if childrenField.dirty {
                    profiler.count("layout.children.rebuilt")
                    var built: [any LayoutObject] = []
                    var pool: ChildReuse = ChildReuse(
                        prior: childrenField.peek() ?? [],
                        enabled: reusesChildren
                    )
                    var prev: (any LayoutObject)? = nil
                    var inlineRun: [any DOMNode] = []
                    var pendingRunIn: Element? = nil
                    for child in node.children {
                        if let el = child as? Element, BlockLayout.hiddenElements.contains(el.tag) {
                            continue
                        }
                        let isBlock: Bool = child.style["display"] == "block"
                        if isBlock {
                            if let el = child as? Element, el.tag == "h6" {
                                if !inlineRun.isEmpty {
                                    let run: [any DOMNode] = inlineRun
                                    let anon: BlockLayout = pool.takeRun(run, previous: prev) {
                                        BlockLayout(nodes: run, parent: self, previous: prev)
                                    }
                                    built.append(anon)
                                    prev = anon
                                    inlineRun = []
                                }
                                pendingRunIn = el
                            } else {
                                if !inlineRun.isEmpty {
                                    let run: [any DOMNode] = inlineRun
                                    let anon: BlockLayout = pool.takeRun(run, previous: prev) {
                                        BlockLayout(nodes: run, parent: self, previous: prev)
                                    }
                                    built.append(anon)
                                    prev = anon
                                    inlineRun = []
                                }
                                if let runIn = pendingRunIn {
                                    let run: [any DOMNode] = [runIn, child]
                                    let next: BlockLayout = pool.takeRun(run, previous: prev) {
                                        BlockLayout(nodes: run, parent: self, previous: prev)
                                    }
                                    built.append(next)
                                    prev = next
                                    pendingRunIn = nil
                                } else {
                                    let next: BlockLayout = pool.takeBlock(child, previous: prev) {
                                        BlockLayout(node: child, parent: self, previous: prev)
                                    }
                                    built.append(next)
                                    if child.style["position"] != "absolute" { prev = next }
                                }
                            }
                        } else {
                            inlineRun.append(child)
                        }
                    }
                    if !inlineRun.isEmpty {
                        let run: [any DOMNode] = inlineRun
                        let anon: BlockLayout = pool.takeRun(run, previous: prev) {
                            BlockLayout(nodes: run, parent: self, previous: prev)
                        }
                        built.append(anon)
                    }
                    if let runIn = pendingRunIn {
                        let next: BlockLayout = pool.takeBlock(runIn, previous: prev) {
                            BlockLayout(node: runIn, parent: self, previous: prev)
                        }
                        built.append(next)
                    }
                    childrenField.set(built)
                }
            } else if reusesChildren, inlineBuilt {
                profiler.count("layout.mode.inline")
                if subtreeStale {
                    profiler.measure("layout.inline.refresh", { refreshInlineItems() })
                }
                profiler.measure("layout.inline.place", { placeInlineItems() })
            } else {
                profiler.count("layout.mode.inline")
                fontByNode.removeAll()
                itemsByNode = [:]
                refreshInlineItems()
                placeInlineItems()
            }
        }
        if skippedChildren { return }

        for child in children { child.layout(reusesChildren: reusesChildren) }

        let sumHeight: Double = profiler.measure("layout.height", {
            children.reduce(0) {
                if $1.node.style["position"] == "absolute" { return $0 }
                var h: CGFloat = $1.height
                if $1 is BlockLayout {
                    h += marginPx($1.node, "margin-top") + marginPx($1.node, "margin-bottom")
                }
                return $0 + h
            }
        })

        if let hStr = node.style["height"], hStr.hasSuffix("px"),
            let h = Double(hStr.dropLast(2))
        {
            contentHeight = sumHeight
            height = scaled(CGFloat(h))
        } else {
            contentHeight = sumHeight
            height = sumHeight
        }

        if let el = node as? Element, el.attributes["id"] == "toc" {
            height += VSTEP
        }

        if let el = node as? Element, el.style["overflow"] == "scroll" {
            let maxScroll: CGFloat = max(0, contentHeight - height)
            scrollOffset = min(el.scrollOffsetY, maxScroll)
        }
    }

    private var subtreeStale: Bool {
        if node.layoutDirty { return true }
        return extraNodes.contains(where: { $0.layoutDirty })
    }

    private func layoutMode() -> String {
        if !extraNodes.isEmpty { return "inline" }
        if node is TextNode { return "inline" }
        let hasBlockChild: Bool = node.children.contains(where: {
            $0.style["display"] == "block"
        })
        if hasBlockChild { return "block" }
        if let el = node as? Element {
            return (el.children.isEmpty && el.tag != "input" && el.tag != "img" && el.tag != "iframe" && el.tag != "canvas") ? "block" : "inline"
        }
        return "inline"
    }

    private func marginPx(_ n: any DOMNode, _ prop: String) -> CGFloat {
        guard let s = n.style[prop], s.hasSuffix("px"), let v = Double(s.dropLast(2)) else { return 0 }
        return scaled(CGFloat(v))
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
        let oldChildren: [any LayoutObject] = childrenField.peek() ?? []

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

        var reused: Int = 0
        if !subtreeStale, TextDirection(cssValue: node.style["direction"]) != .rtl {
            for (i, object) in children.enumerated() where i < oldChildren.count {
                guard let line = object as? LineLayout,
                    let old = oldChildren[i] as? LineLayout,
                    sameLine(old, line)
                else {
                    continue
                }
                line.prelaid = geometry(of: old)
                line.paintCache = old.paintCache
                line.paintGeneration = old.paintGeneration
                reused += 1
            }
        }

        profiler.count("layout.lines.total", by: children.count)
        profiler.count("layout.lines.reused", by: reused)
    }

    private func sameLine(_ old: LineLayout, _ new: LineLayout) -> Bool {
        guard !old.hasEmbed, !new.hasEmbed else { return false }
        guard old.children.count == new.children.count else { return false }
        for index in old.children.indices {
            guard old.children[index] === new.children[index] else { return false }
        }
        return true
    }

    private func geometry(of line: LineLayout) -> LineGeometry {
        LineGeometry(x: line.x, y: line.y, height: line.height)
    }

    private func refreshInlineItems() {
        var leaves: [any DOMNode] = []
        if extraNodes.isEmpty {
            collectLeaves(node, into: &leaves)
        } else {
            for n in extraNodes { collectLeaves(n, into: &leaves) }
        }
        var items: [InlineItem] = []
        var cache: [ObjectIdentifier: [InlineItem]] = [:]
        cache.reserveCapacity(leaves.count)
        for leaf in leaves {
            let key: ObjectIdentifier = ObjectIdentifier(leaf)
            if let cached = itemsByNode[key], !leaf.layoutDirty {
                items.append(contentsOf: cached)
                cache[key] = cached
                continue
            }
            fontByNode.removeValue(forKey: key)
            let rebuilt: [InlineItem] = makeItems(for: leaf)
            items.append(contentsOf: rebuilt)
            cache[key] = rebuilt
        }
        inlineItems = items
        itemsByNode = cache
        inlineBuilt = true
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
        let mode: WhiteSpaceMode = WhiteSpaceMode(cssValue: textNode.style["white-space"])
        let font: BrowserFont = font(for: textNode)
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
        items.append(.text(makeText(run: run, word: word, display: nil, font: run.font)))
    }

    private func makeText(run: InlineTextRun, word: String, display: String?, font: BrowserFont) -> TextLayout {
        let text: TextLayout = TextLayout(node: run.node, word: word, parent: nil, previous: nil)
        text.font = font
        text.fontOverride = font
        text.displayWord = display
        text.whiteSpace = run.whiteSpace
        text.cacheMetrics()
        return text
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

    private func placeText(_ text: TextLayout) {
        let w: CGFloat = text.textWidth
        if cursorX + w > width && text.whiteSpace.wraps {
            if text.word.contains("\u{00AD}") {
                let parts: [String] = text.word.components(separatedBy: "\u{00AD}")
                var chunk: String = ""
                var breakIdx: Int = -1
                for (i, part) in parts.dropLast().enumerated() {
                    let candidate: String = chunk + part + "-"
                    if cursorX + text.font.measure(candidate) <= width {
                        chunk = chunk + part
                        breakIdx = i
                    }
                }
                if breakIdx >= 0 {
                    appendToLine(clone(text, word: chunk + "-"))
                    newLine()
                    placeText(clone(text, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}")))
                    return
                }
            }
            newLine()
        }
        appendToLine(text)
        cursorX += text.advance
    }

    private func appendToLine(_ text: TextLayout) {
        let line: any LayoutObject = children.last!
        text.parent = line
        text.previous = line.children.last
        line.children.append(text)
    }

    private func clone(_ text: TextLayout, word: String) -> TextLayout {
        let copy: TextLayout = TextLayout(node: text.node, word: word, parent: nil, previous: nil)
        copy.font = text.font
        copy.fontOverride = text.font
        copy.whiteSpace = text.whiteSpace
        copy.cacheMetrics()
        return copy
    }

    private func font(for node: any DOMNode) -> BrowserFont {
        let nodeID: ObjectIdentifier = ObjectIdentifier(node)
        if let cached = fontByNode[nodeID] { return cached }
        profiler.count("text.fontNodes")
        let weight: String = node.style["font-weight"] ?? "normal"
        var style: String = node.style["font-style"] ?? "normal"
        if style == "normal" { style = "roman" }
        let sizePx: Double = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let resolved: BrowserFont = getFont(
            size: Int(scaled(sizePx)),
            weight: weight,
            style: style,
            family: node.style["font-family"] ?? "serif"
        )
        fontByNode[nodeID] = resolved
        return resolved
    }

    private func newLine() {
        cursorX = 0
        let lastLine: (any LayoutObject)? = children.last
        let line: LineLayout = LineLayout(node: node, parent: self, previous: lastLine)
        children.append(line)
    }

    private func addInput(_ node: Element) {
        if node.attributes["type"] == "hidden" { return }

        let w: CGFloat = BlockLayout.inputWidthPx
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let input: InputLayout = InputLayout(node: node, parent: line, previous: prevItem)
        line.children.append(input)

        let weight: String = node.style["font-weight"] ?? "normal"
        var style: String = node.style["font-style"] ?? "normal"
        if style == "normal" { style = "roman" }
        let sizePx: Double = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt: Int = Int(sizePx)
        let font: BrowserFont = getFont(
            size: sizeInt, weight: weight, style: style,
            family: node.style["font-family"] ?? "serif")
        cursorX += w + font.spaceWidth
    }

    private func addButton(_ node: Element) {
        let w: CGFloat = InputLayout.inputWidthPx
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let button: ButtonLayout = ButtonLayout(node: node, parent: line, previous: prevItem)
        line.children.append(button)
        let font: BrowserFont = getFont(size: 12, weight: "normal", style: "roman")
        cursorX += w + font.spaceWidth
    }

    private func addImage(_ node: Element) {
        let w: CGFloat = ImageLayout.usedWidth(for: node, available: width, zoom: zoom)
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let image: ImageLayout = ImageLayout(node: node, parent: line, previous: prevItem)
        line.children.append(image)

        let font: BrowserFont = fontForElement(node, zoom: zoom)
        cursorX += w + font.spaceWidth
    }

    private func addIframe(_ node: Element) {
        let w: CGFloat = scaled(IframeLayout.displaySize(for: node).width)
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let iframe: IframeLayout = IframeLayout(node: node, parent: line, previous: prevItem)
        line.children.append(iframe)

        let font: BrowserFont = fontForElement(node, zoom: zoom)
        cursorX += w + font.spaceWidth
    }

    private func addCanvas(_ node: Element) {
        let w: CGFloat = scaled(CanvasLayout.contentSize(for: node).width)
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prevItem: (any LayoutObject)? = line.children.last
        let canvas: CanvasLayout = CanvasLayout(node: node, parent: line, previous: prevItem)
        line.children.append(canvas)

        let font: BrowserFont = fontForElement(node, zoom: zoom)
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
        let weight: String = node.style["font-weight"] ?? "normal"
        var styleStr: String = node.style["font-style"] ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx: Double = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt: Int = Int(sizePx)
        let smallSize: Int = Int(Double(sizeInt))
        let family: String = node.style["font-family"] ?? "serif"

        for (text, isLower) in runs {
            let displayText: String = isLower ? text.uppercased() : text
            let font: BrowserFont =
                isLower
                ? getFont(size: smallSize, weight: "bold", style: styleStr, family: family)
                : getFont(size: sizeInt, weight: weight, style: styleStr, family: family)
            items.append(.text(makeText(run: run, word: text, display: displayText, font: font)))
        }
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
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

        if let border: DrawOutline = DrawOutline.fromBorderStyle(node, rect: selfRect()) {
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
                items.append(drawCursor(last, offset: last.width))
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

// MARK: - ChildReuse

@MainActor
private struct ChildReuse {
    enum Kind {
        case block
        case run
    }

    private var prior: [any LayoutObject]
    private var index: Int = 0
    private var byNode: [ObjectIdentifier: any LayoutObject]? = nil

    init(prior: [any LayoutObject], enabled: Bool) {
        self.prior = enabled ? prior : []
    }

    mutating func takeBlock(
        _ node: any DOMNode,
        previous: (any LayoutObject)?,
        _ make: () -> BlockLayout
    ) -> BlockLayout {
        reuse(.block, first: node, run: [], previous: previous, make)
    }

    mutating func takeRun(
        _ run: [any DOMNode],
        previous: (any LayoutObject)?,
        _ make: () -> BlockLayout
    ) -> BlockLayout {
        guard let first = run.first else { return make() }
        return reuse(.run, first: first, run: run, previous: previous, make)
    }

    private mutating func reuse(
        _ kind: Kind,
        first: any DOMNode,
        run: [any DOMNode],
        previous: (any LayoutObject)?,
        _ make: () -> BlockLayout
    ) -> BlockLayout {
        if byNode == nil, index < prior.count,
            let block = prior[index] as? BlockLayout,
            matches(block, kind: kind, first: first, run: run)
        {
            index += 1
            block.previous = previous
            return block
        }
        buildIndex()
        guard let candidate = byNode?.removeValue(forKey: ObjectIdentifier(first)),
            let block = candidate as? BlockLayout,
            matches(block, kind: kind, first: first, run: run)
        else { return make() }
        block.previous = previous
        return block
    }

    private mutating func buildIndex() {
        guard byNode == nil else { return }
        var map: [ObjectIdentifier: any LayoutObject] = [:]
        map.reserveCapacity(prior.count - index)
        for i in index..<prior.count {
            map[ObjectIdentifier(prior[i].node)] = prior[i]
        }
        byNode = map
    }

    private func matches(
        _ block: BlockLayout,
        kind: Kind,
        first: any DOMNode,
        run: [any DOMNode]
    ) -> Bool {
        guard block.node === first else { return false }
        switch kind {
        case .block:
            return block.extraNodes.isEmpty
        case .run:
            guard block.extraNodes.count == run.count else { return false }
            return zip(block.extraNodes, run).allSatisfy({ $0 === $1 })
        }
    }
}
