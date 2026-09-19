import CoreGraphics

struct ScrollbarGeometry {
    let docHeight: CGFloat
    let contentHeight: CGFloat
    let contentWidth: CGFloat
    let scroll: CGFloat
}

func scrollbarBarRect(
    _ geometry: ScrollbarGeometry,
    forcedColors: Bool,
    topInset: CGFloat = 0
) -> DrawRect? {
    let maxScroll: CGFloat = max(geometry.docHeight - geometry.contentHeight, 0)
    guard maxScroll > 0 else { return nil }
    let barHeight: CGFloat = max((geometry.contentHeight / geometry.docHeight) * geometry.contentHeight, 30)
    let barTop: CGFloat = (geometry.scroll / maxScroll) * (geometry.contentHeight - barHeight)
    return DrawRect(
        rect: Rect(
            left: geometry.contentWidth - 8,
            top: topInset + barTop,
            right: geometry.contentWidth,
            bottom: topInset + barTop + barHeight
        ),
        color: forcedColors ? ForcedColor.canvasText : "blue"
    )
}
