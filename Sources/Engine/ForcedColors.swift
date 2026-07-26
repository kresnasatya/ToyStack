import CoreGraphics

// MARK: - Forced Colors Palette
// The user's palette for high-contrast mode. Every name is already
// understood by Color(cssName:) in PaintCommand.swift.
public enum ForcedColor {
    public static let canvas = "black"
    public static let canvasText = "white"
    public static let linkText = "yellow"
    public static let visitedText = "orchid"
    public static let buttonFace = "black"
    public static let buttonText = "white"
    public static let buttonBorder = "white"
    public static let highlight = "gold"
}

let forcedColorsMarker = "-forced-colors"

func isForcedColors(_ node: any DOMNode) -> Bool {
    node.style[forcedColorsMarker] == "active"
}

func ringColors(_ node: any DOMNode) -> (outer: String, inner: String) {
    isForcedColors(node)
        ? (ForcedColor.highlight, ForcedColor.canvas)
        : ("white", "black")
}

func forceColors(node: any DOMNode) {
    node.style[forcedColorsMarker] = "active"

    guard let element = node as? Element else { return }

    element.style["color"] = ForcedColor.canvasText

    if let bg = element.style["background-color"], bg != "transparent" {
        element.style["background-color"] = ForcedColor.canvas
    }

    if element.style["border-color"] != nil {
        element.style["border-color"] = ForcedColor.buttonBorder
    }

    switch element.tag {
        case "a":
            element.style["color"] = ForcedColor.linkText
        case "input", "button":
            element.style["color"] = ForcedColor.buttonText
            element.style["background-color"] = ForcedColor.buttonFace
        default:
            break
    }
}
