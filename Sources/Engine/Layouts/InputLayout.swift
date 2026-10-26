import CoreGraphics

// MARK: - InputLayout
@MainActor
class InputLayout: LayoutObject, InlineLayoutItem {

    static let inputWidthPx: CGFloat = 200

    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
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

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.widthField = ProtectedField("width", node: node, parent: parent)
        self.heightField = ProtectedField("height", node: node, parent: parent)
        self.xField = ProtectedField("x", node: node, parent: parent)
        self.yField = ProtectedField("y", node: node, parent: parent)
        self.zoomField = ProtectedField("zoom", node: node, parent: parent)
        self.node = node
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
    }

    func layout() {
        zoom = resolvedZoom()
        guard let element = node as? Element else { return }

        let weight: String = element.style["font-weight"] ?? "normal"
        var styleStr: String = element.style["font-style"] ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx: Double = Double(element.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt: Int = Int(scaled(sizePx))
        font = getFont(
            size: sizeInt, weight: weight, style: styleStr,
            family: element.style["font-family"] ?? "serif"
        )

        let zoom: CGFloat = zoomField.read(notify: widthField)
        widthField.set(InputLayout.inputWidthPx * zoom)
        if (node as? Element)?.attributes["type"] == "checkbox" {
            widthField.set(font.linespace)
        }

        if let prev = previous as? InlineLayoutItem {
            let space: CGFloat = prev.font.spaceWidth
            x = prev.x + space + prev.width
        } else {
            x = parent!.x
        }
        height = font.linespace
    }

    func shouldPaint() -> Bool {
        true
    }

    func paint(into items: inout [any DisplayItem]) {
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
