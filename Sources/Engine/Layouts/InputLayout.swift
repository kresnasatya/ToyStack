import CoreGraphics

// MARK: - InputLayout
class InputLayout: LayoutObject, InlineLayoutItem {

    static let inputWidthPx: CGFloat = 200

    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1.0

    var font: BrowserFont = inlineDefaultFont

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
    }

    func layout() {
        zoom = computeZoom(node, parentZoom: parent!.zoom)
        guard let element = node as? Element else { return }

        let weight: String = element.style["font-weight"] ?? "normal"
        var styleStr: String = element.style["font-style"] ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx: Double = Double(element.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt: Int = Int(dpx(sizePx * 0.75, zoom: zoom))
        font = getFont(
            size: sizeInt, weight: weight, style: styleStr,
            family: element.style["font-family"] ?? "serif")

        width = dpx(InputLayout.inputWidthPx, zoom: zoom)
        if (node as? Element)?.attributes["type"] == "checkbox" {
            width = font.linespace
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

    func paint() -> [any PaintItem] {
        guard let element = node as? Element else {
            return []
        }
        var cmds: [any PaintCommand] = []

        let bgcolor: String = element.style["background-color"] ?? "transparent"
        let radiusStr: String = (element.style["border-radius"] ?? "0px").replacingOccurrences(
            of: "px", with: "")
        let borderRadius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
        if bgcolor != "transparent" {
            if borderRadius > 0 {
                cmds.append(
                    DrawRRect(
                        rect: selfRect(), parentEffect: nil, radius: borderRadius,
                        color: bgcolor))
            } else {
                cmds.append(DrawRect(rect: selfRect(), color: bgcolor))
            }
        }

        if element.attributes["type"] == "checkbox" {
            cmds.append(DrawRect(rect: selfRect(), color: isForcedColors(node) ? ForcedColor.buttonFace : "white"))
            cmds.append(DrawOutline(rect: selfRect(), color: isForcedColors(node) ? ForcedColor.buttonBorder : "black", thickness: 1))
            if element.isChecked {
                cmds.append(
                    DrawText(
                        at: CGPoint(x: x, y: y),
                        text: "X",
                        font: font,
                        color: isForcedColors(node) ? ForcedColor.buttonText : "black"
                    )
                )
            }
            let outline: DrawOutline? = cssOutline(node, rect: selfRect())
            if element.isFocusVisible && outline == nil {
                cmds.append(DrawOutline(rect: selfRect(), color: ringColors(node).outer, thickness: 2))
                cmds.append(DrawOutline(rect: selfRect(), color: ringColors(node).inner, thickness: 4))
            }
            if let outline = outline { cmds.append(outline) }
            return cmds
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
        cmds.append(DrawText(at: CGPoint(x: x, y: y), text: text, font: font, color: color))

        if element.isFocused {
            // NOTE: cx = caret X
            // The caret X is the x-position of the blinking text cursor when the input has focus.
            let cx: CGFloat = x + font.measure(text)
            cmds.append(
                DrawLine(
                    from: CGPoint(x: cx, y: y),
                    to: CGPoint(x: cx, y: y + height),
                    color: isForcedColors(node) ? ForcedColor.buttonText : "black",
                    thickness: 1
                )
            )
        }
        let outline: DrawOutline? = cssOutline(node, rect: selfRect())
        if element.isFocusVisible && outline == nil {
            cmds.append(DrawOutline(rect: selfRect(), color: ringColors(node).outer, thickness: 4))
            cmds.append(DrawOutline(rect: selfRect(), color: ringColors(node).inner, thickness: 2))
        }
        if let outline = outline { cmds.append(outline) }

        return cmds
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
