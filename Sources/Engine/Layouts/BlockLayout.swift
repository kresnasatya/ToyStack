import CoreGraphics

// MARK: - BlockLayout
// Lays out one DOM node, either stacking block children or flowing inline content.
class BlockLayout: LayoutObject {
    // Tags that force block layout mode when found among siblings.
    static let blockElements: Set<String> = [
        "html", "body", "article", "section", "nav",
        "aside", "h1", "h2", "h3", "h4", "h5", "h6", "hgroup",
        "header", "foother", "address", "p", "hr", "pre",
        "blockquote", "ol", "ul", "menu", "li", "dl",
        "dt", "dd", "figure", "figcaption", "main", "div",
        "table", "form", "fieldset", "legend", "details", "summary",
    ]
    static let inputWidthPx: CGFloat = 200
    static let paragraphSpacing: CGFloat = 18.0

    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0

    // cursorX tracks the horizontal position within the current inline line.
    private var cursorX: CGFloat = 0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        x = parent!.x
        width = parent!.width
        // Stack below the previous sibling, or start at the parent's y.
        y = previous.map { $0.y + $0.height } ?? parent!.y

        let mode = layoutMode()
        if mode == "block" {
            // Block mode: one BlockLayout per DOM child, stacked vertically.
            var prev: (any LayoutObject)? = nil
            for child in node.children {
                let next = BlockLayout(node: child, parent: self, previous: prev)
                children.append(next)
                prev = next
            }
        } else {
            // Inline mode: wrap text and inputs into lines.
            newLine()
            recurse(node)
        }

        for child in children { child.layout() }
        // Height is the sum of all children's heights.
        height = children.reduce(0) { $0 + $1.height }
    }

    // Returns "block" if any child Element has a block-level tag; else "inline".
    private func layoutMode() -> String {
        if node is TextNode { return "inline" }
        let hasBlockChild = node.children.contains(where: {
            guard let el = $0 as? Element else { return false }
            return BlockLayout.blockElements.contains(el.tag)
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
            let segments = textNode.text.components(separatedBy: "\n")
            for (i, segment) in segments.enumerated() {
                if i > 0 { paragraphBreak() }
                for word in segment.split(whereSeparator: { $0.isWhitespace }) {
                    addWord(node: n, word: String(word))
                }
            }
        } else if let el = n as? Element {
            if el.tag == "br" {
                newLine()
            } else if el.tag == "input" || el.tag == "button" {
                addInput(el)
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
        let sizeInt = Int(sizePx * 0.75)
        let font = getFont(size: sizeInt, weight: weight, style: style)
        let w = font.measure(word)

        if cursorX + w > width { newLine() }
        let line = children.last!
        let prevWord = line.children.last
        let textLayout = TextLayout(node: node, word: word, parent: line, previous: prevWord)
        line.children.append(textLayout)
        // cursorX not increment here; LineLayout handles positioning in layout().
    }

    private func paragraphBreak() {
        newLine()  // close current line; new empty line become the spacer
        if let spacer = children.last as? LineLayout {
            spacer.minHeight = BlockLayout.paragraphSpacing
        }
        newLine()  // fresh line ready for next words.
    }

    // Starts a new LineLayout row for inline content.
    private func newLine() {
        cursorX = 0
        let lastLine = children.last
        let line = LineLayout(node: node, parent: self, previous: lastLine)
        children.append(line)
    }

    // Adds a fixed-width InputLayout to the current line.
    private func addInput(_ node: Element) {
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
        let font = getFont(size: sizeInt, weight: weight, style: style)
        cursorX += w + font.measure(" ")
    }

    // The bounding rectangle for this block.
    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }

    // Emits a DrawRect if this element has a non-transparent background color
    func paint() -> [any PaintCommand] {
        let bgcolor = node.style["background-color"] ?? "transparent"
        guard bgcolor != "transparent" else { return [] }
        return [DrawRect(rect: selfRect(), color: bgcolor)]
    }

    // <input> and <button> are painted by InputLayout, not BlockLayout.
    func shouldPaint() -> Bool {
        if node is TextNode { return true }
        guard let el = node as? Element else { return true }
        return el.tag != "input" && el.tag != "button"
    }
}
