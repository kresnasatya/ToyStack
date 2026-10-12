import CoreGraphics

// MARK: - CanvasOp
enum CanvasOp {
    case fillRect(Rect, String)
    case clearRect(Rect)
    case strokeRect(Rect, String, CGFloat)
    case fillPath(CGPath, String)
    case strokePath(CGPath, String, CGFloat)
    case fillText(String, Point, String, BrowserFont)
    case drawImage(CGImage, Rect)

    func draw(cg: CGContext, renderer: CGRenderer) {
        switch self {
            case .fillRect(let rect, let color):
                renderer.fillRect(rect, color: BrowserColor(cssName: color))
            case .clearRect(let rect):
                cg.clear(rect.cgRect)
            case .strokeRect(let rect, let color, let width):
                renderer.strokeRect(rect, color: BrowserColor(cssName: color), lineWidth: width)
            case .fillPath(let path, let color):
                cg.saveGState()
                cg.setFillColor(BrowserColor(cssName: color).cgColor)
                cg.addPath(path)
                cg.fillPath()
                cg.restoreGState()
            case .strokePath(let path, let color, let width):
                cg.saveGState()
                cg.setStrokeColor(BrowserColor(cssName: color).cgColor)
                cg.setLineWidth(width)
                cg.addPath(path)
                cg.strokePath()
                cg.restoreGState()
            case .fillText(let text, let point, let color, let font):
                renderer.drawText(text, font: font, color: BrowserColor(cssName: color), at: Point(x: point.x, y: point.y - font.ascent))
            case .drawImage(let image, let rect):
                renderer.drawImage(image, in: rect)
        }
    }
}
