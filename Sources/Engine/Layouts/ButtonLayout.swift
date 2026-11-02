import Foundation

@MainActor
class ButtonLayout: EmbedLayout {

    private var cursorX: CGFloat = 0

    override init(
        node: DOMRef,
        parent: any LayoutObject,
        previous: (any LayoutObject)?
    ) {
        super.init(node: node, parent: parent, previous: previous)
        // The first inner-line pass runs before the containing line can place this button.
        // Seed a known y so that pass does not read a dirty field;
        // the line overwrites it, then re-lays out this button.
        xField.set(0)
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
        if xField.isDirty {
            xField.set(0)
        }
        if yField.isDirty {
            yField.set(0)
        }
        let contentDirty: Bool = hasDirtyDescendants
            || fields.isDirty(.width) || fields.isDirty(.height)
            || fields.isDirty(.zoom) || fields.isDirty(.font)
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

    private func recurse(_ n: DOMRef) {
        if let textNode = n.text {
            for word in textNode.text.split(whereSeparator: { $0.isWhitespace }) {
                addWord(node: n, word: String(word))
            }
        } else if let el = n.element {
            if el.tag == "br" {
                newLine()
            } else if el.tag == "input" {
                addInput(el)
            } else {
                for child in n.children { recurse(child) }
            }
        }
    }

    private func addWord(node: DOMRef, word: String) {
        let font: BrowserFont = fontForElement(node, zoom: zoom, notify: fontField)
        let w: CGFloat = font.measure(word)
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prev: (any LayoutObject)? = line.children.last
        let textLayout: TextLayout = TextLayout(node: node, word: word, parent: line, previous: prev)
        textLayout.fontOverride = font
        line.children.append(textLayout)
        cursorX += w
    }

    private func addInput(_ node: ElementRef) {
        let font: BrowserFont = fontForElement(node.ref, zoom: zoom, notify: fontField)
        let isCheckbox: Bool = node.attributes["type"] == "checkbox"
        let w: CGFloat = isCheckbox ? font.linespace : scaled(InputLayout.inputWidthPx)
        if cursorX + w > width { newLine() }
        let line: any LayoutObject = children.last!
        let prev: (any LayoutObject)? = line.children.last
        line.children.append(InputLayout(node: node.ref, parent: line, previous: prev))
        cursorX += w
    }

    override func shouldPaint() -> Bool {
        true
    }

    override func paint(into items: inout [DisplayOp]) {
        guard let element = node.element else { return }
        let computed: ComputedStyle = element.style.computed
        let displayColor: BrowserColor = computed.visual.background.color
            ?? BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonFace : "white")
        items.append(.rect(rect: selfRect(), color: displayColor))
        items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonBorder : "black"), width: 1))

        let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
        if element.isFocusVisible && outline == nil {
            items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: focusRingColors(node).outer), width: 4))
            items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: focusRingColors(node).inner), width: 2))
        }
        if let outline = outline { items.append(outline) }
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
