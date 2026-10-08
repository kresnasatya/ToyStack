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

func splitScrollbars(_ items: [any DisplayItem]) -> (content: [any DisplayItem], bars: [any DisplayItem]) {
    var content: [any DisplayItem] = []
    var bars: [any DisplayItem] = []
    for item in items {
        if item is ScrollbarBar {
            bars.append(item)
            continue
        }
        guard let effect = item as? BrowserVisualEffect else {
            content.append(item)
            continue
        }
        let (childContent, childBars) = splitScrollbars(effect.children)
        effect.children = childContent
        if !childBars.isEmpty {
            bars.append(effect.clone(children: childBars))
        }
        if !childContent.isEmpty || effect is Clip {
            content.append(effect)
        }
    }
    return (content, bars)
}
