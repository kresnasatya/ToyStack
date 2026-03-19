import Foundation

class ButtonLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    // Outer LineLayout sets y after layout() runs, leaving inner children positioned
    // at y=0. When y changes, shift all inner LineLayouts and their children (TextLayouts,
    // InputLayouts) by the same delta to keep them correctly placed inside the button.
    var y: CGFloat = 0 {
        didSet {
            guard y != oldValue else { return }
            let delta = y - oldValue
            for child in children {  // inner Lineyouts
                child.y += delta
                for grandchild in child.children {  // TextLayouts
                    grandchild.y += delta
                }
            }
        }
    }
    var width: CGFloat = 0
    var height: CGFloat = 0
    var font: BrowserFont = getFont(size: 12, weight: "normal", style: "roman")

    private var cursorX: CGFloat = 0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        guard let element = node as? Element else { return }

        let weight = element.style["font-weight"] ?? "normal"
        var styleStr = element.style["font-style"] ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx = Double(element.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt = Int(sizePx * 0.75)
        font = getFont(
            size: sizeInt, weight: weight, style: styleStr,
            family: element.style["font-family"] ?? "serif")

        width = InputLayout.inputWidthPx
        if let prev = previous as? InlineLayoutItem {
            x = prev.x + prev.font.measure(" ") + prev.width
        } else {
            x = parent!.x
        }

        newLine()
        for child in element.children { recurse(child) }
        for child in children { child.layout() }

        height = children.reduce(0) { $0 + $1.height }
        if height == 0 { height = font.linespace }
    }

    private func newLine() {
        cursorX = 0
        let line = LineLayout(node: node, parent: self, previous: children.last)
        children.append(line)
    }

    private func recurse(_ n: any DOMNode) {
        if let textNode = n as? TextNode {
            for word in textNode.text.split(whereSeparator: { $0.isWhitespace }) {
                addWord(node: n, word: String(word))
            }
        } else if let el = n as? Element {
            if el.tag == "br" {
                newLine()
            } else if el.tag == "input" {
                addInput(el)
            } else {
                for child in el.children { recurse(child) }
            }
        }
    }

    private func addWord(node: any DOMNode, word: String) {
        let weight = node.style["font-weight"] ?? "normal"
        var style = node.style["font-style"] ?? "normal"
        if style == "normal" { style = "roman" }
        let sizePx = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt = Int(sizePx * 0.75)
        let font = getFont(
            size: sizeInt, weight: weight, style: style,
            family: node.style["font-family"] ?? "serif")
        let w = font.measure(word)
        if cursorX + w > width { newLine() }
        let line = children.last!
        let prev = line.children.last
        line.children.append(TextLayout(node: node, word: word, parent: line, previous: prev))
        cursorX += w
    }

    private func addInput(_ node: Element) {
        let w = InputLayout.inputWidthPx
        if cursorX + w > width { newLine() }
        let line = children.last!
        let prev = line.children.last
        line.children.append(InputLayout(node: node, parent: line, previous: prev))
        cursorX += w
    }

    func shouldPaint() -> Bool {
        true
    }

    func paint() -> [any PaintCommand] {
        guard let element = node as? Element else { return [] }
        var cmds: [any PaintCommand] = []
        let bgcolor = element.style["background-color"] ?? "transparent"
        let displayColor = bgcolor == "transparent" ? "white" : bgcolor
        cmds.append(DrawRect(rect: selfRect(), color: displayColor, source: self))
        cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 1))
        return cmds
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
