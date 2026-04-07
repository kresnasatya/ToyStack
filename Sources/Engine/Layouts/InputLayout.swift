import CoreGraphics
import SwiftUI

// MARK: - InputLayout
// Lays out <input> and <button> elements at a fixed width 200px.
// Paints background, text content, and a focus cursor.
class InputLayout: LayoutObject, InlineLayoutItem {

    static let inputWidthPx: CGFloat = 200

    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []  // always empty
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1.0

    // font is set during layout(); LineLayout reads it for baseline alignment.
    var font: BrowserFont = getFont(size: 12, weight: "normal", style: "roman")

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
        node.layoutObject = self
    }

    func layout() {
        zoom = parent!.zoom
        guard let element = node as? Element else { return }

        let weight = element.style["font-weight"] ?? "normal"
        var styleStr = element.style["font-style"] ?? "normal"
        if styleStr == "normal" { styleStr = "roman" }
        let sizePx = Double(element.style["font-size"]?.dropLast(2) ?? "16") ?? 16.0
        let sizeInt = Int(dpx(sizePx * 0.75, zoom: zoom))
        font = getFont(
            size: sizeInt, weight: weight, style: styleStr,
            family: element.style["font-family"] ?? "serif")

        width = dpx(InputLayout.inputWidthPx, zoom: zoom)
        if (node as? Element)?.attributes["type"] == "checkbox" {
            width = font.linespace
        }

        if let prev = previous as? InlineLayoutItem {
            let space = prev.font.measure(" ")
            x = prev.x + space + prev.width
        } else {
            x = parent!.x
        }
        height = font.linespace
    }

    func shouldPaint() -> Bool {
        true
    }

    func paint() -> [Any] {
        guard let element = node as? Element else {
            return []
        }
        var cmds: [any PaintCommand] = []

        // 1. Background color and radius.
        let bgcolor = element.style["background-color"] ?? "transparent"
        let radiusStr = (element.style["border-radius"] ?? "0px").replacingOccurrences(
            of: "px", with: "")
        let borderRadius = CGFloat(Double(radiusStr) ?? 0)
        if bgcolor != "transparent" {
            if borderRadius > 0 {
                cmds.append(
                    DrawRRect(
                        rect: selfRect(), parentEffect: nil, radius: borderRadius,
                        color: bgcolor))
            } else {
                cmds.append(DrawRect(rect: selfRect(), color: bgcolor, source: self))
            }
        }

        // For input checkbox
        if element.attributes["type"] == "checkbox" {
            cmds.append(DrawRect(rect: selfRect(), color: "white", source: self))
            cmds.append(DrawOutline(rect: selfRect(), color: "black", thickness: 1))
            if element.isChecked {
                cmds.append(
                    DrawText(x1: x, y1: y, text: "X", font: font, color: "black", source: self))
            }
            return cmds
        }

        // 2. Text: the value attribute for <input>, the label for <button>.
        var text = ""
        if element.tag == "input" {
            let value = element.attributes["value"] ?? ""
            // For input type password, mask their content
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
        let color = element.style["color"] ?? "black"
        cmds.append(DrawText(x1: x, y1: y, text: text, font: font, color: color, source: self))

        // 3. Cursor line when this element has focus (user is typing into it)
        if element.isFocused {
            let cx = x + font.measure(text)
            cmds.append(
                DrawLine(
                    x1: cx, y1: y, x2: cx, y2: y + height, color: "black", thickness: 1,
                    source: self))
        }

        return paintVisualEffects(node: node, cmds: cmds, rect: selfRect())
    }

    // The bounding rectangle for background and hit-testing.
    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }
}
