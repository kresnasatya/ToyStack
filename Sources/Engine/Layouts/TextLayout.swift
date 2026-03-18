import CoreGraphics

// MARK: - TextLayout
// Lays out one word within a line. Computes font, width, and x-position.
// y is set later by LineLayout during baseline alignment.
class TextLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let word: String
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []  // always empty - words have no children
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    // font is set during layout(); LineLayout reads it for baseline aligment.
    var font: BrowserFont = getFont(size: 12, weight: "normal", style: "roman")
    var fontOverride: BrowserFont? = nil
    var displayWord: String? = nil

    init(node: any DOMNode, word: String, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.word = word
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        let weight = node.style["font-weight"] ?? "normal"
        var styleStr = node.style["font-style"] ?? "normal"
        // CSS uses "italic"; tkinter/CoreText uses "italic" too, but "roman" = normal.
        if styleStr == "normal" { styleStr = "roman" }

        let sizePx = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt = Int(sizePx * 0.75)  // CSS px -> typhographic points
        font =
            fontOverride
            ?? getFont(
                size: sizeInt, weight: weight, style: styleStr,
                family: node.style["font-family"] ?? "serif")
        width = font.measure(displayWord ?? word) + font.measure(" ")

        if let prev = previous as? InlineLayoutItem {
            x = prev.x + prev.width
        } else {
            x = parent!.x
        }

        height = font.linespace  // used by LineLayout to compute line height
    }

    func paint() -> [any PaintCommand] {
        let color = node.style["color"] ?? "black"
        return [
            DrawText(
                x1: x, y1: y, text: displayWord ?? word, font: font, color: color, source: self)
        ]
    }

    func shouldPaint() -> Bool {
        true
    }
}
