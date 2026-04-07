import CoreGraphics

// MARK: - BlockLayout
// Lays out one DOM node, either stacking block children or flowing inline content.
class BlockLayout: LayoutObject {
    // Tags that must not appear in layout tree.
    static let hiddenElements: Set<String> = ["head", "title", "script", "style"]

    static let inputWidthPx: CGFloat = 200
    static let paragraphSpacing: CGFloat = 18.0
    static let liIndent: CGFloat = 20.0
    static let bulletSize: CGFloat = 8.0

    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    let extraNodes: [any DOMNode]  // non-empty = anonymous block box
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1.0

    // cursorX tracks the horizontal position within the current inline line.
    private var cursorX: CGFloat = 0

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
        zoom = parent!.zoom
        x = parent!.x
        if let wStr = node.style["width"], wStr.hasSuffix("px"), let w = Double(wStr.dropLast(2)) {
            width = CGFloat(w)
        } else {
            width = parent!.width
        }

        if let el = node as? Element, el.tag == "li" {
            x += BlockLayout.liIndent
            width -= BlockLayout.liIndent
        }

        // Stack below the previous sibling, or start at the parent's y.
        y = previous.map { $0.y + $0.height } ?? parent!.y

        if let el = node as? Element, el.attributes["id"] == "toc" {
            y += VSTEP
        }

        let mode = layoutMode()
        if mode == "block" {
            var prev: (any LayoutObject)? = nil
            var inlineRun: [any DOMNode] = []
            var pendingRunIn: Element? = nil

            for child in node.children {
                if let el = child as? Element, BlockLayout.hiddenElements.contains(el.tag) {
                    continue
                }
                let isBlock = child.style["display"] == "block"
                if isBlock {
                    if let el = child as? Element, el.tag == "h6" {
                        if !inlineRun.isEmpty {
                            let anon = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
                            children.append(anon)
                            prev = anon
                            inlineRun = []
                        }
                        pendingRunIn = el
                    } else {
                        if !inlineRun.isEmpty {
                            let anon = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
                            children.append(anon)
                            prev = anon
                            inlineRun = []
                        }
                        if let runIn = pendingRunIn {
                            let next = BlockLayout(
                                nodes: [runIn, child], parent: self, previous: prev)
                            children.append(next)
                            prev = next
                            pendingRunIn = nil
                        } else {
                            let next = BlockLayout(node: child, parent: self, previous: prev)
                            children.append(next)
                            prev = next
                        }
                    }
                } else {
                    inlineRun.append(child)
                }
            }
            if !inlineRun.isEmpty {
                let anon = BlockLayout(nodes: inlineRun, parent: self, previous: prev)
                children.append(anon)
            }
            if let runIn = pendingRunIn {
                let next = BlockLayout(node: runIn, parent: self, previous: prev)
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

        for child in children { child.layout() }

        if let hStr = node.style["height"], hStr.hasSuffix("px"),
            let h = Double(hStr.dropLast(2))
        {
            height = CGFloat(h)
        } else {
            // Height is the sum of all children's heights.
            height = children.reduce(0) { $0 + $1.height }
        }

        if let el = node as? Element, el.attributes["id"] == "toc" {
            height += VSTEP
        }
    }

    // Returns "block" if any child has display:block in its computed style; else "inline"
    private func layoutMode() -> String {
        if !extraNodes.isEmpty { return "inline" }
        if node is TextNode { return "inline" }
        let hasBlockChild = node.children.contains(where: {
            $0.style["display"] == "block"
        })
        if hasBlockChild { return "block" }
        if let el = node as? Element {
            return (el.children.isEmpty && el.tag != "input") ? "block" : "inline"
        }
        return "inline"
    }

    // Walks inline DOM content: text nodes produces words, elements produces inputs.
    private func recurse(_ n: any DOMNode) {
        if let textNode = n as? TextNode {
            if isInsidePre(textNode) {
                let segments = textNode.text.components(separatedBy: "\n")
                for (i, segment) in segments.enumerated() {
                    if i > 0 { newLine() }
                    if !segment.isEmpty { addWord(node: n, word: segment) }
                }
            } else {
                for word in textNode.text.split(whereSeparator: { $0.isWhitespace }) {
                    addWord(node: n, word: String(word))
                }
            }
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

    // Adds a word to the current line, starting a new line if needed.
    private func addWord(node: any DOMNode, word: String) {
        let weight = node.style["font-weight"] ?? "normal"
        var style = node.style["font-style"] ?? "normal"
        if style == "normal" { style = "roman" }
        let sizePx = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt = Int(dpx(sizePx * 0.75, zoom: zoom))
        let font = getFont(
            size: sizeInt, weight: weight, style: style,
            family: node.style["font-family"] ?? "serif")
        let w = font.measure(word)

        if isInsideAbbr(node) && word.contains(where: { $0.isLowercase }) {
            addAbbrWord(node: node, word: word)
            return
        }

        if cursorX + w > width && !isInsidePre(node) {
            if word.contains("\u{00AD}") {
                let parts = word.components(separatedBy: "\u{00AD}")
                var chunk = ""
                var breakIdx = -1
                for (i, part) in parts.dropLast().enumerated() {
                    let candidate = chunk + part + "-"
                    if cursorX + font.measure(candidate) <= width {
                        chunk = chunk + part
                        breakIdx = i
                    }
                }
                if breakIdx >= 0 {
                    let line = children.last!
                    let prev = line.children.last
                    line.children.append(
                        TextLayout(node: node, word: chunk + "-", parent: line, previous: prev))
                    newLine()
                    addWord(
                        node: node, word: parts[(breakIdx + 1)...].joined(separator: "\u{00AD}"))
                    return
                }
            }
            newLine()
        }

        let line = children.last!
        let prevWord = line.children.last
        let textLayout = TextLayout(node: node, word: word, parent: line, previous: prevWord)
        line.children.append(textLayout)
        // cursorX not increment here; LineLayout handles positioning in layout().
    }

    // Starts a new LineLayout row for inline content.
    private func newLine() {
        cursorX = 0
        let lastLine = children.last
        let line = LineLayout(node: node, parent: self, previous: lastLine)
        if let el = node as? Element, el.tag == "h1", el.attributes["class"] == "title" {
            line.centered = true
        }
        children.append(line)
    }

    // Adds a fixed-width InputLayout to the current line.
    private func addInput(_ node: Element) {
        // For input type hidden
        if node.attributes["type"] == "hidden" { return }

        let w = BlockLayout.inputWidthPx
        if cursorX + w > width { newLine() }
        let line = children.last!
        let prevItem = line.children.last
        let input = InputLayout(node: node, parent: line, previous: prevItem)
        line.children.append(input)

        let weight = node.style["font-weight"] ?? "normal"
        var style = node.style["font-style"] ?? "normal"
        if style == "normal" { style = "roman" }
        let sizePx = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt = Int(sizePx * 0.75)
        let font = getFont(
            size: sizeInt, weight: weight, style: style,
            family: node.style["font-family"] ?? "serif")
        cursorX += w + font.measure(" ")
        width = dpx(BlockLayout.inputWidthPx, zoom: zoom)
    }

    private func addButton(_ node: Element) {
        let w = InputLayout.inputWidthPx
        if cursorX + w > width { newLine() }
        let line = children.last!
        let prevItem = line.children.last
        let button = ButtonLayout(node: node, parent: line, previous: prevItem)
        line.children.append(button)
        let font = getFont(size: 12, weight: "normal", style: "roman")
        cursorX += w + font.measure(" ")
    }

    private func isInsideAbbr(_ node: any DOMNode) -> Bool {
        var current = node.parent
        while let c = current {
            if let el = c as? Element, el.tag == "abbr" { return true }
            current = c.parent
        }
        return false
    }

    private func isInsidePre(_ node: any DOMNode) -> Bool {
        var current: (any DOMNode)? = node
        while let c = current {
            if let el = c as? Element, el.tag == "pre" {
                return true
            }
            current = c.parent
        }
        return false
    }

    private func addAbbrWord(node: any DOMNode, word: String) {
        // Split into runs: (text, isLowerCase)
        var runs: [(String, Bool)] = []
        for ch in word {
            let isLower = ch.isLowercase
            if runs.last?.1 == isLower {
                runs[runs.count - 1].0.append(ch)
            } else {
                runs.append((String(ch), isLower))
            }
        }

        let weight = node.style["font-weight"] ?? "normal"
        var styleStr = node.style["font-style"] ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt = Int(sizePx * 0.75)
        let smallSize = Int(Double(sizeInt) * 0.75)  // 75% of normal

        for (text, isLower) in runs {
            let displayText = isLower ? text.uppercased() : text
            let font =
                isLower
                ? getFont(
                    size: smallSize, weight: "bold", style: styleStr,
                    family: node.style["font-family"] ?? "serif")
                : getFont(
                    size: sizeInt, weight: weight, style: styleStr,
                    family: node.style["font-family"] ?? "serif")
            let w = font.measure(displayText)
            if cursorX + w > width { newLine() }
            let line = children.last!
            let prev = line.children.last
            let textLayout = TextLayout(node: node, word: text, parent: line, previous: prev)
            textLayout.fontOverride = font
            textLayout.displayWord = displayText
            line.children.append(textLayout)
        }
    }

    // The bounding rectangle for this block.
    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }

    // Emits a DrawRect if this element has a non-transparent background color
    func paint() -> [Any] {
        var commands: [Any] = []
        let bgcolor = node.style["background-color"] ?? "transparent"
        if bgcolor != "transparent" {
            commands.append(DrawRect(rect: self.selfRect(), color: bgcolor, source: self))
        }

        let borderStyle = node.style["border-style"] ?? "none"
        if borderStyle != "none",
            let widthStr = node.style["border-width"],
            let borderPx = Double(widthStr.dropLast(2))
        {
            let color = node.style["border-color"] ?? "black"
            commands.append(
                DrawOutline(rect: selfRect(), color: color, thickness: CGFloat(borderPx)))
        }

        if let el = node as? Element, el.tag == "li" {
            let bulletX = x - BlockLayout.liIndent
            let bulletY = y + (VSTEP - BlockLayout.bulletSize) / 2
            let bulletRect = Rect(
                left: bulletX, top: bulletY, right: bulletX + BlockLayout.bulletSize,
                bottom: bulletY + BlockLayout.bulletSize
            )
            commands.append(DrawRect(rect: bulletRect, color: "black", source: self))
        }

        if let el = node as? Element, el.attributes["id"] == "toc" {
            let headerRect = Rect(left: x, top: y - VSTEP, right: x + width, bottom: y)
            commands.append(DrawRect(rect: headerRect, color: "gray", source: self))
            let font = getFont(size: 12, weight: "bold", style: "roman")
            commands.append(
                DrawText(
                    x1: x, y1: y - VSTEP, text: "Table of Contents", font: font, color: "white",
                    source: self))
        }

        return commands
    }

    // <input> and <button> are painted by InputLayout, not BlockLayout.
    func shouldPaint() -> Bool {
        if node is TextNode { return true }
        guard let el = node as? Element else { return true }
        return el.tag != "input" && el.tag != "button"
    }
}
