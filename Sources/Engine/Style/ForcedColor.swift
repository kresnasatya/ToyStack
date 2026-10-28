import CoreGraphics

// MARK: - Forced Colors Palette
public enum ForcedColor {
    public static let canvas: String = "black"
    public static let canvasText: String = "white"
    public static let linkText: String = "yellow"
    public static let visitedText: String = "orchid"
    public static let buttonFace: String = "black"
    public static let buttonText: String = "white"
    public static let buttonBorder: String = "white"
    public static let highlight: String = "gold"
}

let forcedColorsAppliedKey: String = "-forced-colors"

@MainActor
func usesForcedColors(_ node: any DOMNode) -> Bool {
    node.style[forcedColorsAppliedKey] == "active"
}

func applyForcedColors(to style: inout [String: String], node: any DOMNode) {
    style[forcedColorsAppliedKey] = "active"

    guard let element = node as? Element else { return }

    style["color"] = ForcedColor.canvasText

    if let bg = style["background-color"], bg != "transparent" {
        style["background-color"] = ForcedColor.canvas
    }

    if style["border-color"] != nil {
        style["border-color"] = ForcedColor.buttonBorder
    }

    if style["outline-color"] != nil {
        style["outline-color"] = ForcedColor.highlight
    }

    switch element.tag {
        case "a":
            style["color"] = ForcedColor.linkText
        case "input", "button":
            style["color"] = ForcedColor.buttonText
            style["background-color"] = ForcedColor.buttonFace
        default:
            break
    }
}
