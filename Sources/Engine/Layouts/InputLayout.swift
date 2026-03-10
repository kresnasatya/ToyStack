import CoreGraphics

// MARK: - InputLayout
// Lays out <input> and <button> elements at a fixed width 200px.
// Paints background, text content, and a focus cursor.
class InputLayout: LayoutObject, InlineLayoutItem {

    static let inputWidthPx: CGFloat = 200

    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []  // always empty
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    // font is set during layout(); LineLayout reads it for baseline alignment.
    var font: BrowserFont = getFont(size: 12, weight: "normal", style: "roman")

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
        font = getFont(size: sizeInt, weight: weight, style: styleStr)

        // All inputs have the same fixed width regardless of content
        width = InputLayout.inputWidthPx

        if let prev = previous as? InlineLayoutItem {
            let space = prev.font.measure(" ")
            x = prev.x + space + prev.width
        } else {
            x = parent!.x
        }
        height = font.linespace
    }

    func shouldPaint() -> Bool {
        true
    }

    func paint() -> [any PaintCommand] {
        guard let element = node as? Element else {
            return []
        }
        var cmds: [any PaintCommand] = []

        // 1. Background color.
        let bgcolor = element.style["background-color"] ?? "transparent"
        if bgcolor != "transparent" {
            cmds.append(DrawRect(rect: selfRect(), color: bgcolor))
        }

        // 2. Text: the value attribute for <input>, the label for <button>.
        var text = ""
        if element.tag == "input" {
            text = element.attributes["value"] ?? ""
        } else if element.tag == "button" {
            if element.children.count == 1,
                let textNode = element.children[0] as? TextNode
            {
                text = textNode.text
            }
        }
        let color = element.style["color"] ?? "black"
        cmds.append(DrawText(x1: x, y1: y, text: text, font: font, color: color))

        // 3. Cursor line when this element has focus (user is typing into it)
        if element.isFocused {
            let cx = x + font.measure(text)
            cmds.append(
                DrawLine(x1: cx, y1: y, x2: cx, y2: y + height, color: "black", thickness: 1))
        }
        return cmds
    }

    // The bounding rectangle for background and hit-testing.
    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
