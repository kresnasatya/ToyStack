import Foundation

@MainActor
class ButtonLayout: EmbedLayout {

    private var cursorX: CGFloat = 0

    override init(
        node: any DOMNode,
        parent: any LayoutObject,
        previous: (any LayoutObject)?
    ) {
        super.init(node: node, parent: parent, previous: previous)
        // The first inner-line pass runs before the containing line can place this button.
        // Seed a known y so that pass does not read a dirty field;
        // the line overwrites it, then re-lays out this button.
        yField.set(0)
        widthField.setDependencies([zoomField])
        heightField.setDependencies([fontField])
        ascentField.setDependencies([fontField])
        descentField.setDependencies([fontField])
    }

    override func layout() {
        if !layoutNeeded() { return }
        defer { hasDirtyDescendants = false }
        // The containing line places this button after its children lay out.
        // Seed a known y so the inner line can lay out before that placement.
        if yField.isDirty {
            yField.set(0)
        }
        let contentDirty: Bool = hasDirtyDescendants || widthField.dirty || heightField.dirty || zoomField.dirty || fontField.dirty
        super.layout()
        guard contentDirty else { return }

        widthField.set(InputLayout.inputWidthPx * zoomField.read(notify: widthField))

        children = []
        newLine()
        for child in node.children { recurse(child) }
        for child in children { child.layout() }

        heightField.setDependencies([fontField] + children.map({ $0.heightField }))
        let contentHeight: CGFloat = children.reduce(0) { $0 + $1.height }
        heightField.set(contentHeight == 0 ? fontField.read(notify: heightField).linespace : contentHeight)

        // A button is an inline container: its baseline stays the font baseline.
        ascentField.set(fontField.read(notify: ascentField).ascent)
        descentField.set(fontField.read(notify: descentField).descent)
    }

    private func newLine() {
        cursorX = 0
        let line: LineLayout = LineLayout(node: node, parent: self, previous: children.last)
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
        let owner: any DOMNode = node.inheritedStyleOwner
        let weight: String = owner.style.read("font-weight", notify: fontField) ?? "normal"
        var style: String = owner.style.read("font-style", notify: fontField) ?? "normal"
        if style == "normal" { style = "roman" }
        let sizePx: Double = Double(owner.style.read("font-size", notify: fontField)?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt: Int = Int(scaled(sizePx))
        let font: BrowserFont = getFont(
            size: sizeInt,
            weight: weight,
            style: style,
            family: owner.style.read("font-family", notify: fontField) ?? "serif"
        )
        let w: CGFloat = font.measure(word)
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prev: (any LayoutObject)? = line.children.last
        let textLayout: TextLayout = TextLayout(node: node, word: word, parent: line, previous: prev)
        textLayout.fontOverride = font
        line.children.append(textLayout)
        cursorX += w
    }

    private func addInput(_ node: Element) {
        let font: BrowserFont = fontForElement(node, zoom: zoom, notify: fontField)
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : scaled(InputLayout.inputWidthPx)
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prev: (any LayoutObject)? = line.children.last
        line.children.append(InputLayout(node: node, parent: line, previous: prev))
        cursorX += w
    }

    override func shouldPaint() -> Bool {
        true
    }

    override func paint(into items: inout [any DisplayItem]) {
        guard let element = node as? Element else { return }
        let bgcolor: String = element.style["background-color"] ?? "transparent"
        let displayColor: String = bgcolor == "transparent" ? (usesForcedColors(node) ? ForcedColor.buttonFace : "white") : bgcolor
        items.append(DrawRect(rect: selfRect(), color: displayColor))
        items.append(DrawOutline(rect: selfRect(), color: usesForcedColors(node) ? ForcedColor.buttonBorder : "black", thickness: 1))

        let outline: DrawOutline? = DrawOutline.fromStyle(node, rect: selfRect())
        if element.isFocusVisible && outline == nil {
            items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).outer, thickness: 4))
            items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).inner, thickness: 2))
        }
        if let outline = outline { items.append(outline) }
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
