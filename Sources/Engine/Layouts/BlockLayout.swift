import CoreGraphics

// MARK: - BlockLayout
class BlockLayout: LayoutObject {
    static let hiddenElements: Set<String> = ["head", "title", "script", "style"]

    static let inputWidthPx: CGFloat = 200
    static let paragraphSpacing: CGFloat = 18.0
    static let liIndent: CGFloat = 20.0
    static let bulletSize: CGFloat = 8.0

    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    let extraNodes: [any DOMNode]
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1.0

    private var cursorX: CGFloat = 0
    private var fontByNode: [ObjectIdentifier: BrowserFont] = [:]

    var scrollOffset: CGFloat = 0
    var contentHeight: CGFloat = 0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.extraNodes = []
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
    }

    init(nodes: [any DOMNode], parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = nodes[0]
        self.extraNodes = nodes
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        profiler.measure("layout.block.build") {
            zoom = computeZoom(node, parentZoom: parent!.zoom)
            let isAbsolute: Bool = node.style["position"] == "absolute"
            if isAbsolute, let lStr = node.style["left"], lStr.hasSuffix("px"),
                let l = Double(lStr.dropLast(2))
            {
                x = CGFloat(l)
            } else {
                x = parent!.x
            }
            if let wStr = node.style["width"], wStr.hasSuffix("px"), let w = Double(wStr.dropLast(2)) {
                width = CGFloat(w)
            } else {
                width = parent!.width
            }

            if let el = node as? Element, el.tag == "li" {
                x += BlockLayout.liIndent
                width -= BlockLayout.liIndent
            }

            if isAbsolute, let tStr = node.style["top"], tStr.hasSuffix("px"),
                let t = Double(tStr.dropLast(2))
            {
                y = CGFloat(t)
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

            let mode: String = layoutMode()
            if mode == "block" {
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
                                let anon: BlockLayout = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
                                children.append(anon)
                                prev = anon
                                inlineRun = []
                            }
                            pendingRunIn = el
                        } else {
                            if !inlineRun.isEmpty {
                                let anon: BlockLayout = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
                                children.append(anon)
                                prev = anon
                                inlineRun = []
                            }
                            if let runIn = pendingRunIn {
                                let next: BlockLayout = BlockLayout(
                                    nodes: [runIn, child], parent: self, previous: prev)
                                children.append(next)
                                prev = next
                                pendingRunIn = nil
                            } else {
                                let next: BlockLayout = BlockLayout(node: child, parent: self, previous: prev)
                                children.append(next)
                                if child.style["position"] != "absolute" { prev = next }
                            }
                        }
                    } else {
                        inlineRun.append(child)
                    }
                }
                if !inlineRun.isEmpty {
                    let anon: BlockLayout = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
                    children.append(anon)
                }
                if let runIn = pendingRunIn {
                    let next: BlockLayout = BlockLayout(node: runIn, parent: self, previous: prev)
                    children.append(next)
                }
            } else {
                newLine()
                if !extraNodes.isEmpty {
                    for n in extraNodes { recurse(n) }
                } else {
                    recurse(node)
                }
            }
        }

        for child in children { child.layout() }

        let sumHeight: Double = children.reduce(0) {
            if $1.node.style["position"] == "absolute" { return $0 }
            var h: CGFloat = $1.height
            if $1 is BlockLayout {
                h += marginPx($1.node, "margin-top") + marginPx($1.node, "margin-bottom")
            }
            return $0 + h
        }
        if let hStr = node.style["height"], hStr.hasSuffix("px"),
            let h = Double(hStr.dropLast(2))
        {
            contentHeight = sumHeight
            height = CGFloat(h)
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

    private func layoutMode() -> String {
        if !extraNodes.isEmpty { return "inline" }
        if node is TextNode { return "inline" }
        let hasBlockChild: Bool = node.children.contains(where: {
            $0.style["display"] == "block"
        })
        if hasBlockChild { return "block" }
        if let el = node as? Element {
            return (el.children.isEmpty && el.tag != "input") ? "block" : "inline"
        }
        return "inline"
    }

    private func marginPx(_ n: any DOMNode, _ prop: String) -> CGFloat {
        guard let s = n.style[prop], s.hasSuffix("px"), let v = Double(s.dropLast(2)) else { return 0 }
        return dpx(CGFloat(v), zoom: zoom)
    }

    private func recurse(_ n: any DOMNode) {
        if let textNode = n as? TextNode {
            addTextNode(textNode)
        } else if let el = n as? Element {
            if el.tag == "br" {
                newLine()
            } else if el.tag == "input" {
                addInput(el)
            } else if el.tag == "button" {
                addButton(el)
            } else {
                for child in el.children { recurse(child) }
            }
        }
    }

    private func addTextNode(_ textNode: TextNode) {
        let mode: WhiteSpace = WhiteSpace.mode(of: textNode)
        if mode.keepsNewlines {
            let segments: [String] = textNode.text.components(separatedBy: "\n")
            for (i, segment) in segments.enumerated() {
                if i > 0 { newLine() }
                addSegment(node: textNode, text: segment, mode: mode)
            }
        } else {
            addSegment(node: textNode, text: textNode.text, mode: mode)
        }
    }

    private func addSegment(node: any DOMNode, text: String, mode: WhiteSpace) {
        if mode.keepSpaces {
            if !text.isEmpty { addWord(node: node, word: text) }
        } else {
            for word in text.split(whereSeparator: { $0.isWhitespace }) {
                addWord(node: node, word: String(word))
            }
        }
    }

    private func addWord(node: any DOMNode, word: String) {
        profiler.count("text.words")
        let font: BrowserFont
        let nodeID: ObjectIdentifier = ObjectIdentifier(node)
        if let cachedFont = fontByNode[nodeID] {
            font = cachedFont
        } else {
            profiler.count("text.fontNodes")
            let weight: String = node.style["font-weight"] ?? "normal"
            var style: String = node.style["font-style"] ?? "normal"
            if style == "normal" { style = "roman" }
            let sizePx: Double = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
            let sizeInt: Int = Int(dpx(sizePx * 0.75, zoom: zoom))
            font = getFont(
                size: sizeInt, weight: weight, style: style,
                family: node.style["font-family"] ?? "serif")
            fontByNode[nodeID] = font
        }
        let w: CGFloat = font.measure(word)

        if isInsideAbbr(node) && word.contains(where: { $0.isLowercase }) {
            addAbbrWord(node: node, word: word)
            return
        }

        let mode: WhiteSpace = WhiteSpace.mode(of: node)
        if cursorX + w > width && mode.wraps {
            if word.contains("\u{00AD}") {
                let parts: [String] = word.components(separatedBy: "\u{00AD}")
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
                    let line: any LayoutObject = children.last!
                    let prev: (any LayoutObject)? = line.children.last
                    let chunkText: TextLayout = TextLayout(
                        node: node,
                        word: chunk + "-",
                        parent: line,
                        previous: prev
                    )
                    chunkText.fontOverride = font
                    line.children.append(chunkText)
                    newLine()
                    addWord(
                        node: node, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}"))
                    return
                }
            }
            newLine()
        }

        let line: any LayoutObject = children.last!
        let prevWord: (any LayoutObject)? = line.children.last
        let textLayout: TextLayout = TextLayout(node: node, word: word, parent: line, previous: prevWord)
        textLayout.fontOverride = font
        line.children.append(textLayout)
        cursorX += w + font.spaceWidth
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
        let sizeInt: Int = Int(sizePx * 0.75)
        let font: BrowserFont = getFont(
            size: sizeInt, weight: weight, style: style,
            family: node.style["font-family"] ?? "serif")
        cursorX += w + font.spaceWidth
        width = dpx(BlockLayout.inputWidthPx, zoom: zoom)
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

    private func isInsideAbbr(_ node: any DOMNode) -> Bool {
        var current: (any DOMNode)? = node.parent
        while let c = current {
            if let el = c as? Element, el.tag == "abbr" { return true }
            current = c.parent
        }
        return false
    }

    private func addAbbrWord(node: any DOMNode, word: String) {
        var runs: [(String, Bool)] = []
        for ch in word {
            let isLower: Bool = ch.isLowercase
            if runs.last?.1 == isLower {
                runs[runs.count - 1].0.append(ch)
            } else {
                runs.append((String(ch), isLower))
            }
        }

        let weight: String = node.style["font-weight"] ?? "normal"
        var styleStr: String = node.style["font-style"] ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx: Double = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt: Int = Int(sizePx * 0.75)
        let smallSize: Int = Int(Double(sizeInt) * 0.75)

        for (text, isLower) in runs {
            let displayText: String = isLower ? text.uppercased() : text
            let font: BrowserFont =
                isLower
                ? getFont(
                    size: smallSize, weight: "bold", style: styleStr,
                    family: node.style["font-family"] ?? "serif")
                : getFont(
                    size: sizeInt, weight: weight, style: styleStr,
                    family: node.style["font-family"] ?? "serif")
            let w: CGFloat = font.measure(displayText)
            if cursorX + w > width { newLine() }
            let line: any LayoutObject = children.last!
            let prev: (any LayoutObject)? = line.children.last
            let textLayout: TextLayout = TextLayout(node: node, word: text, parent: line, previous: prev)
            textLayout.fontOverride = font
            textLayout.displayWord = displayText
            line.children.append(textLayout)
        }
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }

    func paint() -> [Any] {
        var commands: [Any] = []
        let bgcolor: String = node.style["background-color"] ?? "transparent"
        let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(
            of: "px", with: "")
        let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
        if bgcolor != "transparent" || node.style["overflow"] == "scroll" {
            if borderRadius > 0 {
                commands.append(
                    DrawRRect(
                        rect: selfRect(), parentEffect: nil, radius: borderRadius, color: bgcolor)
                )
            } else {
                commands.append(DrawRect(rect: selfRect(), color: bgcolor))
            }
        }

        let borderStyle: String = node.style["border-style"] ?? "none"
        if borderStyle != "none",
            let widthStr = node.style["border-width"],
            let borderPx = Double(widthStr.dropLast(2))
        {
            let color: String = node.style["border-color"] ?? "black"
            commands.append(
                DrawOutline(rect: selfRect(), color: color, thickness: CGFloat(borderPx)))
        }

        let outline: DrawOutline? = cssOutline(node, rect: selfRect())
        if node.isFocusVisible && outline == nil {
            let ring: (outer: String, inner: String) = ringColors(node)
            commands.append(DrawOutline(rect: selfRect(), color: ring.outer, thickness: 4))
            commands.append(DrawOutline(rect: selfRect(), color: ring.inner, thickness: 2))
        }
        if let outline = outline { commands.append(outline) }

        if let el = node as? Element, el.tag == "li" {
            let bulletX: CGFloat = x - BlockLayout.liIndent
            let bulletY: CGFloat = y + (VSTEP - BlockLayout.bulletSize) / 2
            let bulletRect: Rect = Rect(
                left: bulletX, top: bulletY, right: bulletX + BlockLayout.bulletSize,
                bottom: bulletY + BlockLayout.bulletSize
            )
            commands.append(DrawRect(rect: bulletRect, color: isForcedColors(node) ? ForcedColor.canvasText : "black"))
        }

        if let el = node as? Element, el.attributes["id"] == "toc" {
            let headerRect: Rect = Rect(left: x, top: y - VSTEP, right: x + width, bottom: y)
            commands.append(DrawRect(rect: headerRect, color: isForcedColors(node) ? ForcedColor.canvasText : "gray"))
            let font: BrowserFont = getFont(size: 12, weight: "bold", style: "roman")
            commands.append(
                DrawText(
                    at: CGPoint(x: x, y: y),
                    text: "Table of Contents",
                    font: font,
                    color: isForcedColors(node) ? ForcedColor.canvas : "white"
                )
            )
        }

        return commands
    }

    func paintScrollbar() -> [Any] {
        guard node.style["overflow"] == "scroll", contentHeight > height else { return [] }
        let barWidth: CGFloat = 8
        let ratio: CGFloat = height / contentHeight
        let barHeight: CGFloat = ratio * height
        let barTop: CGFloat = y + (scrollOffset / contentHeight) * height
        let barRect: Rect = Rect(
            left: x + width - barWidth, top: barTop, right: x + width, bottom: barTop + barHeight)
        return [DrawRect(rect: barRect, color: isForcedColors(node) ? ForcedColor.canvasText : "gray")]
    }

    func shouldPaint() -> Bool {
        if node is TextNode { return true }
        guard let el = node as? Element else { return true }
        return el.tag != "input" && el.tag != "button"
    }
}
