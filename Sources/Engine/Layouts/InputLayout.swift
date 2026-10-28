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
        super.layout()

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

    override func paint(into items: inout [any DisplayItem]) {
        guard let element = node as? Element else { return }
        let bgcolor: String = element.style["background-color"] ?? "transparent"
        if bgcolor != "transparent" {
            let radii: CornerRadii = CSSValueParser.cornerRadii(element.style) ?? .zero
            if !radii.isZero {
                items.append(
                    DrawRRect(
                        rect: selfRect(),
                        parentEffect: nil,
                        radii: radii,
                        color: bgcolor
                    )
                )
            } else {
                items.append(DrawRect(rect: selfRect(), color: bgcolor))
            }
        }

        if element.attributes["type"] == "checkbox" {
            items.append(DrawRect(rect: selfRect(), color: usesForcedColors(node) ? ForcedColor.buttonFace : "white"))
            items.append(DrawOutline(rect: selfRect(), color: usesForcedColors(node) ? ForcedColor.buttonBorder : "black", thickness: 1))
            if element.isChecked {
                items.append(
                    DrawText(
                        at: Point(x: x, y: y),
                        text: "X",
                        font: font,
                        color: usesForcedColors(node) ? ForcedColor.buttonText : "black"
                    )
                )
            }
            let outline: DrawOutline? = DrawOutline.fromStyle(node, rect: selfRect())
            if element.isFocusVisible && outline == nil {
                items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).outer, thickness: 2))
                items.append(DrawOutline(rect: selfRect(), color: focusRingColors(node).inner, thickness: 4))
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
        items.append(DrawText(at: Point(x: x, y: y), text: text, font: font, color: color))

        if element.isFocused {
            items.append(drawCursor(self, offset: font.measure(text)))
        }
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
