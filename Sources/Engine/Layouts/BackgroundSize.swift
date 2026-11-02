import CoreGraphics

// MARK: - BackgroundSize
struct BackgroundSize {
    let box: Rect
    let image: CGImage
    let zoom: CGFloat

    private var boxWidth: CGFloat { box.right - box.left }
    private var boxHeight: CGFloat { box.bottom - box.top }
    private var intrinsicWidth: CGFloat { CGFloat(image.width) * zoom }
    private var intrinsicHeight: CGFloat { CGFloat(image.height) * zoom }

    func rect(spec: BackgroundSizeSpec) -> Rect {
        let size: (width: CGFloat, height: CGFloat) = resolve(spec: spec)
        return Rect(
            left: box.left,
            top: box.top,
            right: box.left + size.width,
            bottom: box.top + size.height
        )
    }

    private func resolve(spec: BackgroundSizeSpec) -> (width: CGFloat, height: CGFloat) {
        guard intrinsicWidth > 0, intrinsicHeight > 0 else { return (boxWidth, boxHeight) }
        switch spec {
        case .cover:
            let scale: CGFloat = max(boxWidth / intrinsicWidth, boxHeight / intrinsicHeight)
            return (intrinsicWidth * scale, intrinsicHeight * scale)
        case .contain:
            let scale: CGFloat = min(boxWidth / intrinsicWidth, boxHeight / intrinsicHeight)
            return (intrinsicWidth * scale, intrinsicHeight * scale)
        case .auto:
            return (intrinsicWidth, intrinsicHeight)
        case .lengths(let widthLength, let heightLength):
            let width: CGFloat? = widthLength?.resolved(available: boxWidth, zoom: zoom)
            let height: CGFloat? = heightLength?.resolved(available: boxHeight, zoom: zoom)
            if let width, let height { return (width, height) }
            if let width { return (width, width * intrinsicHeight / intrinsicWidth) }
            if let height { return (height * intrinsicWidth / intrinsicHeight, height) }
            return (intrinsicWidth, intrinsicHeight)
        }
    }
}
