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

    func rect(css: String?) -> Rect {
        let tokens: [String] = (css ?? "auto")
            .split(whereSeparator: { $0 == " " }).map(String.init)
        let first: String = tokens.first?.lowercased() ?? "auto"
        let second: String? = tokens.count > 1 ? tokens[1].lowercased() : nil
        let size: (width: CGFloat, height: CGFloat) = resolve(first: first, second: second)
        return Rect(
            left: box.left,
            top: box.top,
            right: box.left + size.width,
            bottom: box.top + size.height
        )
    }

    private func resolve(first: String, second: String?) -> (width: CGFloat, height: CGFloat) {
        guard intrinsicWidth > 0, intrinsicHeight > 0 else { return (boxWidth, boxHeight) }
        switch first {
        case "cover":
            let scale: CGFloat = max(boxWidth / intrinsicWidth, boxHeight / intrinsicHeight)
            return (intrinsicWidth * scale, intrinsicHeight * scale)
        case "contain":
            let scale: CGFloat = min(boxWidth / intrinsicWidth, boxHeight / intrinsicHeight)
            return (intrinsicWidth * scale, intrinsicHeight * scale)
        default:
            let width: CGFloat? = length(first, reference: boxWidth)
            let height: CGFloat? = second.flatMap({ length($0, reference: boxHeight) })
            if let width, let height { return (width, height) }
            if let width { return (width, width * intrinsicHeight / intrinsicWidth) }
            if let height { return (height * intrinsicWidth / intrinsicHeight, height) }
            return (intrinsicWidth, intrinsicHeight)
        }
    }

    private func length(_ token: String, reference: CGFloat) -> CGFloat? {
        if token == "auto" { return nil }
        if token.hasSuffix("%"), let pct = Double(token.dropLast()) {
            return reference * CGFloat(pct) / 100
        }
        if token.hasSuffix("px"), let px = Double(token.dropLast(2)) {
            return CGFloat(px) * zoom
        }
        return nil
    }
}
