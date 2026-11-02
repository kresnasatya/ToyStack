import CoreGraphics

// MARK: - InputLayout
@MainActor
class InputLayout: EmbedLayout {

    static let inputWidthPx: CGFloat = 200

    override init(
        node: DOMRef,
        parent: any LayoutObject,
        previous: (any LayoutObject)?
    ) {
        super.init(node: node, parent: parent, previous: previous)
        widthField.setDependencies([fontField, zoomField])
        heightField.setDependencies([fontField])
    }

    override func layout() {
        if !layoutNeeded() { return }
        let sizeDirty: Bool = fields.isDirty(.width) || fields.isDirty(.height)
            || fields.isDirty(.zoom) || fields.isDirty(.font)
        super.layout()
        guard sizeDirty else { return }
        let isCheckbox: Bool = node.element?.attributes["type"] == "checkbox"
        if isCheckbox {
            widthField.set(fontField.read(notify: widthField).linespace)
        } else {
            widthField.set(InputLayout.inputWidthPx * zoomField.read(notify: widthField))
        }

        heightField.set(fontField.read(notify: heightField).linespace)
        setAscentFromHeight()
    }

    override func shouldPaint() -> Bool {
        true
    }

    override func paint(into items: inout [DisplayOp]) {
        guard let element = node.element else { return }
        let computed: ComputedStyle = element.style.computed
        if let bgcolor: BrowserColor = computed.visual.background.color {
            let radii: CornerRadii = computed.box.decoration.border.radii
            if !radii.isZero {
                items.append(.rrect(rect: selfRect(), radii: radii, color: bgcolor))
            } else {
                items.append(.rect(rect: selfRect(), color: bgcolor))
            }
        }

        if element.attributes["type"] == "checkbox" {
            items.append(.rect(rect: selfRect(), color: BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonFace : "white")))
            items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonBorder : "black"), width: 1))
            if element.isChecked {
                items.append(
                    .text(
                        text: "X",
                        font: font,
                        color: BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonText : "black"),
                        rect: Rect(
                            left: x,
                            top: y,
                            right: x + font.measure("X"),
                            bottom: y + font.linespace
                        )
                    )
                )
            }
            let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
            if element.isFocusVisible && outline == nil {
                items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: focusRingColors(node).outer), width: 2))
                items.append(.outline(rect: selfRect(), color: BrowserColor(cssName: focusRingColors(node).inner), width: 4))
            }
            if let outline = outline { items.append(outline) }
        }

        var text: String = ""
        if element.tag == "input" {
            let value: String = element.attributes["value"] ?? ""
            if element.attributes["type"] == "password" {
                text = String(repeating: "*", count: value.count)
            } else {
                text = value
            }
        } else if element.tag == "button" {
            if element.children.count == 1,
                let textNode = element.children[0].text
            {
                text = textNode.text
            }
        }
        items.append(.text(text: text, font: font, color: computed.text.color, rect: Rect(left: x, top: y, right: font.measure(text), bottom: y + font.linespace)))

        if element.isFocused {
            items.append(drawCursor(self, offset: font.measure(text)))
        }
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
