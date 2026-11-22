import CoreGraphics

// MARK: - ScrollbarStyle
enum ScrollbarStyle {
    static let thumbWidth: CGFloat = 8
    static let thumbInset: CGFloat = 2
    static let thumbRadius: CGFloat = 4
    static let thumbMinHeight: CGFloat = 30
    static let thumbColor: String = "#757575"
}

struct ScrollbarGeometry {
    static let minPageFraction: CGFloat = 0.875
    static let maxPageOverlap: CGFloat = 40

    let docHeight: CGFloat
    let contentHeight: CGFloat
    let contentWidth: CGFloat
    let scroll: CGFloat

    var maxScroll: CGFloat { max(docHeight - contentHeight, 0) }

    var thumbHeight: CGFloat {
        return max((contentHeight / docHeight) * contentHeight, ScrollbarStyle.thumbMinHeight)
    }

    var thumbTravel: CGFloat { contentHeight - thumbHeight }

    var pageStep: CGFloat {
        return max(contentHeight * ScrollbarGeometry.minPageFraction, contentHeight - ScrollbarGeometry.maxPageOverlap)
    }

    var thumbRect: Rect? {
        guard maxScroll > 0 else { return nil }
        let top: CGFloat = (scroll / maxScroll) * thumbTravel
        return Rect(
            left: contentWidth - ScrollbarStyle.thumbInset - ScrollbarStyle.thumbWidth,
            top: top,
            right: contentWidth - ScrollbarStyle.thumbInset,
            bottom: top + thumbHeight
        )
    }

    func thumbGrabContains(x: CGFloat, y: CGFloat) -> Bool {
        guard let thumb: Rect = thumbRect else { return false }
        return gutterContains(x: x) && y >= thumb.top && y < thumb.bottom
    }

    func trackPageDelta(x: CGFloat, y: CGFloat) -> CGFloat? {
        guard let thumb: Rect = thumbRect, gutterContains(x: x), y >= 0, y < contentHeight else { return nil }
        if y < thumb.top {
            return -pageStep
        }
        if y >= thumb.bottom {
            return pageStep
        }
        return nil
    }

    private func gutterContains(x: CGFloat) -> Bool {
        let gutterLeft: CGFloat = contentWidth - ScrollbarStyle.thumbWidth - 2 * ScrollbarStyle.thumbInset
        return x >= gutterLeft && x <= contentWidth
    }

    func scroll(forThumbTop top: CGFloat) -> CGFloat {
        guard maxScroll > 0, thumbTravel > 0 else { return scroll }
        let clamped: CGFloat = min(max(top, 0), thumbTravel)
        return clamped / thumbTravel * maxScroll
    }
}

func scrollbarBarRect(_ geometry: ScrollbarGeometry, forcedColors: Bool) -> DisplayOp? {
    guard let thumb: Rect = geometry.thumbRect else { return nil }
    return .rrect(
        rect: thumb,
        radii: .uniform(.px(ScrollbarStyle.thumbRadius)),
        color: BrowserColor(cssName: forcedColors ? ForcedColor.canvasText : ScrollbarStyle.thumbColor)
    )
}
