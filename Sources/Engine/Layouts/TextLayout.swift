import CoreGraphics

// MARK: - TextLayout
class TextLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let word: String
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1.0

    var font: BrowserFont = inlineDefaultFont
    var fontOverride: BrowserFont? = nil
    var displayWord: String? = nil

    init(node: any DOMNode, word: String, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.word = word
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
    }

    func layout() {
        profiler.measure("layout.text", {
            let resolvedFont: BrowserFont
            if let override = fontOverride {
                resolvedFont = override
            } else {
                zoom = computeZoom(node, parentZoom: parent!.zoom)
                let weight = node.style["font-weight"] ?? "normal"
                var styleStr = node.style["font-style"] ?? "normal"
                if styleStr == "normal" { styleStr = "roman" }
                let sizePx = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
                let sizeInt = Int(dpx(sizePx * 0.75, zoom: zoom))
                resolvedFont = getFont(
                        size: sizeInt,
                        weight: weight,
                        style: styleStr,
                        family: node.style["font-family"] ?? "serif"
                )
            }

            font = resolvedFont
            width = font.measure(displayWord ?? word) + font.spaceWidth

            if let prev = previous as? InlineLayoutItem {
                x = prev.x + prev.width
            } else {
                x = parent!.x
            }

            height = font.linespace
        })
    }

    func paint() -> [Any] {
        let color = node.style["color"] ?? "black"
        return [
            DrawText(
                at: CGPoint(x: x, y: y),
                text: displayWord ?? word,
                font: font,
                color: color
            )
        ]
    }

    func shouldPaint() -> Bool {
        true
    }
}
