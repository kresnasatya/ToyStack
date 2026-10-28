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

    let fontField: ProtectedField<BrowserFont>
    var font: BrowserFont {
        get { fontField.get() }
        set { fontField.set(newValue) }
    }
    let ascentField: ProtectedField<CGFloat>
    let descentField: ProtectedField<CGFloat>
    var fontOverride: BrowserFont? = nil
    var displayWord: String? = nil
    var textWidth: CGFloat = 0
    var whiteSpace: WhiteSpaceMode = .normal

    init(node: any DOMNode, word: String, parent: (any LayoutObject)?, previous: (any LayoutObject)?) {
        self.widthField = ProtectedField("width", node: node, parent: parent)
        self.heightField = ProtectedField("height", node: node, parent: parent)
        self.xField = ProtectedField("x", node: node, parent: parent)
        self.yField = ProtectedField("y", node: node, parent: parent)
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.fontField = ProtectedField(
            owner: FieldOwner(name: "font", node: node, parent: parent),
            equals: { lhs, rhs in CFEqual(lhs.ctFont, rhs.ctFont) },
            cleanValue: inlineDefaultFont
        )
        self.ascentField = ProtectedField(
            "ascent",
            cleanValue: inlineDefaultFont.ascent,
            node: node,
            parent: parent
        )
        self.descentField = ProtectedField(
            "descent",
            cleanValue: inlineDefaultFont.descent,
            node: node,
            parent: parent
        )
        self.node = node
        self.word = word
        self.parent = parent
        self.previous = previous
        node.layoutObject = self

        var zoomInputs: [any InvalidatableField] = [node.style.field("zoom")]
        if let parent { zoomInputs.append(parent.zoomField) }
        zoomField.setDependencies(zoomInputs)

        fontField.setDependencies([zoomField] + fontInputs(for: node))
        widthField.setDependencies([fontField])
        heightField.setDependencies([fontField])
        ascentField.setDependencies([fontField])
        descentField.setDependencies([fontField])

        var xInputs: [any InvalidatableField] = []
        if let parent { xInputs.append(parent.xField) }
        if let previous {
            xInputs.append(previous.xField)
            xInputs.append(previous.widthField)
        }
        xField.setDependencies(xInputs)

        var yInputs: [any InvalidatableField] = [ascentField]
        if let parent {
            yInputs.append(parent.yField)
            if let line = parent as? LineLayout {
                yInputs.append(line.ascentField)
            }
        }
        yField.setDependencies(yInputs)
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants { return true }
        return zoomField.dirty || xField.dirty || yField.dirty
            || widthField.dirty || heightField.dirty
            || fontField.dirty || ascentField.dirty || descentField.dirty
    }

    func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }
        profiler.measure("layout.text", {
            zoomField.set(resolvedZoom())
            let resolvedFont: BrowserFont
            if let override = fontOverride {
                resolvedFont = override
            } else {
                resolvedFont = fontForElement(node, zoom: zoomField.read(notify: fontField), notify: fontField)
            }
            fontField.set(resolvedFont)

            let measuredFont: BrowserFont = fontField.read(notify: widthField)
            let measured: CGFloat = measuredFont.measure(displayWord ?? word)
            textWidth = measured
            widthField.set(measured + measuredFont.spaceWidth)

            heightField.set(fontField.read(notify: heightField).linespace)
            ascentField.set(fontField.read(notify: ascentField).ascent)
            descentField.set(fontField.read(notify: descentField).descent)

            if let previous {
                let prevX: CGFloat = previous.xField.read(notify: xField)
                let prevWidth: CGFloat = previous.widthField.read(notify: xField)
                xField.set(prevX + prevWidth)
            } else {
                xField.copy(from: parent!.xField)
            }
        })
    }

    func paint(into items: inout [any DisplayItem]) {
        let color: String = node.inheritedStyleOwner.style["color"] ?? "black"
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
