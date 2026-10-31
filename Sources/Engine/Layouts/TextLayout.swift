import CoreGraphics

// MARK: - TextLayout
@MainActor
class TextLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let word: String
    weak var parent: (any LayoutObject)?
    var previous: (any LayoutObject)?
    var fields: LayoutFieldStore = LayoutFieldStore()
    var hasDirtyDescendants: Bool = false
    var font: BrowserFont {
        get { fontField.get() }
        set { fontField.set(newValue) }
    }
    var fontOverride: BrowserFont? = nil
    var displayWord: String? = nil
    var textWidth: CGFloat = 0
    var whiteSpace: WhiteSpaceMode = .normal

    init(node: any DOMNode, word: String, parent: (any LayoutObject)?, previous: (any LayoutObject)?) {
        self.node = node
        self.word = word
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
        childrenField.setClean([])
        childrenField.setDependencies([])
        fontField.setClean(inlineDefaultFont)
        ascentField.setClean(inlineDefaultFont.ascent)
        descentField.setClean(inlineDefaultFont.descent)
        markAncestorsDirty()

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
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
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
