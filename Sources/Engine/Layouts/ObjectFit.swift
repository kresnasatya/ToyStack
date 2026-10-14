import CoreGraphics

// MARK: - ObjectFit
struct ObjectFit {
    let box: Rect
    let intrinsicWidth: CGFloat
    let intrinsicHeight: CGFloat
    let css: String?

    private var boxWidth: CGFloat { box.right - box.left }
    private var boxHeight: CGFloat { box.bottom - box.top }

    var contentRect: Rect {
        let size: (width: CGFloat, height: CGFloat) = resolvedSize()
        let dx: CGFloat = (boxWidth - size.width) / 2
        let dy: CGFloat = (boxHeight - size.height) / 2
        return Rect(
            left: box.left + dx,
            top: box.top + dy,
            right: box.right + dx + size.width,
            bottom: box.bottom + dy + size.height
        )
    }

    private func resolvedSize() -> (width: CGFloat, height: CGFloat) {
        guard intrinsicWidth > 0, intrinsicHeight > 0 else { return (boxWidth, boxHeight) }
        let contain: CGFloat = min(boxWidth / intrinsicWidth, boxHeight / intrinsicHeight)
        switch (css ?? "fill").lowercased() {
        case "contain":
            return (intrinsicWidth * contain, intrinsicHeight * contain)
        case "cover":
            let cover: CGFloat = max(boxWidth / intrinsicWidth, boxHeight / intrinsicHeight)
            return (intrinsicWidth * cover, intrinsicHeight * cover)
        case "none":
            return (intrinsicWidth, intrinsicHeight)
        case "scale-down":
            let scale: CGFloat = min(1, contain)
            return (intrinsicWidth * scale, intrinsicHeight * scale)
        default:
            return (boxWidth, boxHeight)
        }
    }
}
