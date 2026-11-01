import CoreGraphics

// MARK: - TextLayout
@MainActor
class TextLayout: LayoutObject, InlineLayoutItem {
    let node: any DOMNode
    let word: String
    weak var parent: (any LayoutObject)?
    var previous: (any LayoutObject)?
    let fields: LayoutFieldStore = LayoutFieldStore()
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
        fontField.mark()
        widthField.setDependencies([fontField])
        heightField.setDependencies([fontField])
        ascentField.setDependencies([fontField])
        descentField.setDependencies([fontField])
        // Position is assigned by the containing line; there are no inputs.
        xField.setDependencies([])
        yField.setDependencies([])
    }

    func layoutNeeded() -> Bool {
        if hasDirtyDescendants {
            profiler.count("layout.dirtyDescendants")
            return true
        }
        return zoomField.dirty || widthField.dirty || heightField.dirty
            || fontField.dirty || ascentField.dirty || descentField.dirty
    }

    func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }
        profiler.measure("layout.text", {
            if zoomField.dirty {
                zoomField.set(resolvedZoom())
            }

            let fontChanged: Bool = fontField.dirty
            if fontChanged {
                let resolvedFont: BrowserFont
                if let override = fontOverride {
                    resolvedFont = override
                } else {
                    resolvedFont = fontForElement(node, zoom: zoomField.read(notify: fontField), notify: fontField)
                }
                fontField.set(resolvedFont)
            }

            if fontChanged || widthField.dirty {
                let measuredFont: BrowserFont = fontField.read(notify: widthField)
                let measured: CGFloat = measuredFont.measure(displayWord ?? word)
                textWidth = measured
                widthField.set(measured + measuredFont.spaceWidth)
            }

            if fontChanged || heightField.dirty {
                heightField.set(fontField.read(notify: heightField).linespace)
            }
            if fontChanged || ascentField.dirty {
                ascentField.set(fontField.read(notify: ascentField).ascent)
            }
            if fontChanged || descentField.dirty {
                descentField.set(fontField.read(notify: descentField).descent)
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

    func detach() {
        parent = nil
        previous = nil
    }

    func attach(to line: LineLayout, previous: (any LayoutObject)?) {
        detach()

        self.parent = line
        self.previous = previous

        zoomField.setDependencies([node.style.field("zoom"), line.zoomField])
    }
}
