import CoreGraphics

// MARK: - TextLayout
@MainActor
class TextLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let word: String
    var parent: (any LayoutObject)?
    var previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var hasDirtyDescendants: Bool = false
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

    var font: BrowserFont = inlineDefaultFont
    var fontOverride: BrowserFont? = nil
    var displayWord: String? = nil
    var textWidth: CGFloat = 0
    var advance: CGFloat = 0
    var whiteSpace: WhiteSpaceMode = .normal
    private(set) var isMeasured: Bool = false

    init(node: any DOMNode, word: String, parent: (any LayoutObject)?, previous: (any LayoutObject)?) {
        self.widthField = ProtectedField("width", node: node, parent: parent)
        self.heightField = ProtectedField("height", node: node, parent: parent)
        self.xField = ProtectedField("x", node: node, parent: parent)
        self.yField = ProtectedField("y", node: node, parent: parent)
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.node = node
        self.word = word
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
    }

    func layout() {
        layout(reusesChildren: false)
    }

    func layout(reusesChildren: Bool) {
        profiler.measure("layout.text", {
            if reusesChildren {
                positionAfterPrevious()
                widthField.set(advance)
                return
            }

            let resolvedFont: BrowserFont
            if let override = fontOverride {
                resolvedFont = override
            } else {
                zoom = resolvedZoom()
                let weight: String = node.style["font-weight"] ?? "normal"
                var styleStr: String = node.style["font-style"] ?? "normal"
                if styleStr == "normal" { styleStr = "roman" }
                let sizePx: Double = Double(node.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
                let sizeInt: Int = Int(scaled(sizePx))
                resolvedFont = getFont(
                        size: sizeInt,
                        weight: weight,
                        style: styleStr,
                        family: node.style["font-family"] ?? "serif"
                )
            }

            font = resolvedFont
            if !isMeasured { cacheMetrics() }
            positionAfterPrevious()
        })
    }

    func cacheMetrics() {
        textWidth = font.measure(displayWord ?? word)
        advance = textWidth + font.spaceWidth
        widthField.set(advance)
        height = font.linespace
        isMeasured = true
    }

    private func positionAfterPrevious() {
        if let prev = previous as? InlineLayoutItem {
            x = prev.x + prev.width
        } else {
            x = parent!.x
        }
    }

    func paint(into items: inout [any DisplayItem]) {
        let color: String = node.style["color"] ?? "black"
        items.append(
            DrawText(
                rect: Rect(
                    left: x,
                    top: y,
                    right: x + textWidth,
                    bottom: y + font.linespace
                ),
                text: displayWord ?? word,
                font: font,
                color: color
            )
        )
    }

    func shouldPaint() -> Bool {
        true
    }
}
