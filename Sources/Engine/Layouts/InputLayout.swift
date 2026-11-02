import CoreGraphics

// MARK: - InputLayout
@MainActor
class InputLayout: EmbedLayout {

    static let inputWidthPx: CGFloat = 200

    override init(
        node: any DOMNode,
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
        let isCheckbox: Bool = (node as? Element)?.attributes["type"] == "checkbox"
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
        guard let element = node as? Element else { return }
        let bgcolor: String = element.style["background-color"] ?? "transparent"
        if bgcolor != "transparent" {
            let radii: CornerRadii = CSSValueParser.cornerRadii(element.style) ?? .zero
            if !radii.isZero {
                items.append(.rrect(selfRect(), radii, BrowserColor(cssName: bgcolor)))
            } else {
                items.append(.rect(selfRect(), BrowserColor(cssName: bgcolor)))
            }
        }

        if element.attributes["type"] == "checkbox" {
            items.append(.rect(selfRect(), BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonFace : "white")))
            items.append(.outline(selfRect(), BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonBorder : "black"), 1))
            if element.isChecked {
                items.append(
                    .text(
                        "X",
                        font,
                        BrowserColor(cssName: usesForcedColors(node) ? ForcedColor.buttonText : "black"),
                        Rect(left: x, top: y, right: x + font.measure("X"), bottom: y + font.linespace
                        )
                    )
                )
            }
            let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
            if element.isFocusVisible && outline == nil {
                items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).outer), 2))
                items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).inner), 4))
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
                let textNode = element.children[0] as? TextNode
            {
                text = textNode.text
            }
        }
        let color: String = element.style["color"] ?? "black"
        items.append(.text(text, font, BrowserColor(cssName: color), Rect(left: x, top: y, right: font.measure(text), bottom: y + font.linespace)))

        if element.isFocused {
            items.append(drawCursor(self, offset: font.measure(text)))
        }
        let outline: DisplayOp? = DisplayOp.fromStyle(node, rect: selfRect())
        if element.isFocusVisible && outline == nil {
            items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).outer), 4))
            items.append(.outline(selfRect(), BrowserColor(cssName: focusRingColors(node).inner), 2))
        }
        if let outline = outline { items.append(outline) }
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
