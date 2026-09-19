import CoreGraphics

// MARK: - CSS outline
func cssOutline(_ node: any DOMNode, rect: Rect) -> DrawOutline? {
    let style: String = node.style["outline-style"] ?? "none"
    guard style != "none", style != "hidden" else { return nil }
    guard let thickness = outlineWidthPx(node.style["outline-width"] ?? "medium"),
        thickness > 0
    else { return nil }
    let color: String = node.style["outline-color"] ?? node.style["color"] ?? "black"
    return DrawOutline(rect: rect, color: color, thickness: thickness)
}

private func outlineWidthPx(_ token: String) -> CGFloat? {
    switch token {
        case "thin": return 1
        case "medium": return 3
        case "thick": return 5
        default:
            guard token.hasSuffix("px"), let value = Double(token.dropLast(2)) else { return nil }
            return CGFloat(value)
    }
}
