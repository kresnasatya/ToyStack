import CoreGraphics

// MARK: - CanvasOp
enum CanvasOp {
    case fillRect(Rect, CanvasPaint)
    case clearRect(Rect)
    case strokeRect(Rect, CanvasPaint, CGFloat)
    case fillPath(CGPath, CanvasPaint)
    case strokePath(CGPath, CanvasPaint, CGFloat)
    case fillText(String, Point, CanvasPaint, BrowserFont)
    case drawImage(CGImage, Rect)

    func draw(cg: CGContext, renderer: CGRenderer) {
        switch self {
            case .fillRect(let rect, let paint):
                paint.fill(CGPath(rect: rect.cgRect, transform: nil), cg: cg)
            case .clearRect(let rect):
                cg.clear(rect.cgRect)
            case .strokeRect(let rect, let paint, let width):
                paint.stroke(CGPath(rect: rect.cgRect, transform: nil), width: width, cg: cg)
            case .fillPath(let path, let paint):
                paint.fill(path, cg: cg)
            case .strokePath(let path, let paint, let width):
                paint.stroke(path, width: width, cg: cg)
            case .fillText(let text, let point, let paint, let font):
                renderer.drawText(text, font: font, color: BrowserColor(cssName: paint.solidColor), at: Point(x: point.x, y: point.y - font.ascent))
            case .drawImage(let image, let rect):
                renderer.drawImage(image, in: rect)
        }
    }
}
