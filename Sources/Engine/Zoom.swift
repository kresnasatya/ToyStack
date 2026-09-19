import CoreGraphics

func computeZoom(_ node: any DOMNode, parentZoom: CGFloat) -> CGFloat {
    guard let zoomStr = node.style["zoom"] else { return parentZoom }
    let trimmed: String = zoomStr.trimmingCharacters(in: .whitespaces)
    let factor: CGFloat
    if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
        factor = CGFloat(pct / 100.0)
    } else if let val = Double(trimmed) {
        factor = CGFloat(val)
    } else {
        return parentZoom
    }
    return parentZoom * factor
}

func dpx(_ cssPx: CGFloat, zoom: CGFloat) -> CGFloat {
    return cssPx * zoom
}
