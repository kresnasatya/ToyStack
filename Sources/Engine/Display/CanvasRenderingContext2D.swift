import CoreGraphics

// MARK: - CanvasRenderingContext2D
final class CanvasRenderingContext2D {
    let width: CGFloat
    let height: CGFloat

    private let cg: CGContext
    private let renderer: CGRenderer
    private var path: CGMutablePath = CGMutablePath()

    private var fillStyle: String = "black"
    private var strokeStyle: String = "black"
    private var font: String = "16px serif"
    private var lineWidth: CGFloat = 1

    init?(width: CGFloat, height: CGFloat, scale: CGFloat) {
        let pxWidth: Int = Int((width * scale).rounded())
        let pxHeight: Int = Int((height * scale).rounded())
        guard pxWidth > 0, pxHeight > 0,
            let cg: CGContext = CGContext(
                data: nil,
                width: pxWidth,
                height: pxHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: height)
        cg.scaleBy(x: 1, y: -1)

        self.width = width
        self.height = height
        self.cg = cg
        self.renderer = CGRenderer(cg: cg, canvasSize: CGSize(width: width, height: height), scale: scale)
    }

    func image() -> CGImage? {
        cg.makeImage()
    }

    func fillRect(_ rect: Rect) {
        renderer.fillRect(rect, color: BrowserColor(cssName: fillStyle))
    }

    func clearRect(_ rect: Rect) {
        cg.clear(rect.cgRect)
    }

    func strokeRect(_ rect: Rect) {
        renderer.strokeRect(rect, color: BrowserColor(cssName: strokeStyle), lineWidth: lineWidth)
    }

    func fillText(_ text: String, at point: Point) {
        let font: BrowserFont = canvasFont()
        renderer.drawText(text, font: font, color: BrowserColor(cssName: fillStyle), at: Point(x: point.x, y: point.y - font.ascent))
    }

    func beginPath() {
        path = CGMutablePath()
    }

    func moveTo(_ point: Point) {
        path.move(to: point.cgPoint)
    }

    func lineTo(_ point: Point) {
        path.addLine(to: point.cgPoint)
    }

    func stroke() {
        cg.saveGState()
        cg.setStrokeColor(BrowserColor(cssName: strokeStyle).cgColor)
        cg.setLineWidth(lineWidth)
        cg.addPath(path)
        cg.strokePath()
        cg.restoreGState()
    }

    func fill() {
        cg.saveGState()
        cg.setFillColor(BrowserColor(cssName: fillStyle).cgColor)
        cg.addPath(path)
        cg.fillPath()
        cg.restoreGState()
    }

    func style(_ key: String) -> String {
        switch key {
            case "fillStyle": return fillStyle
            case "strokeStyle": return strokeStyle
            case "font": return font
            case "lineWidth": return String(Double(lineWidth))
            default: return ""
        }
    }

    func setStyle(_ key: String, _ value: String) {
        switch key {
            case "fillStyle": fillStyle = value
            case "strokeStyle": strokeStyle = value
            case "font": font = value
            case "lineWidth": lineWidth = CGFloat(Double(value) ?? Double(lineWidth))
            default: break

        }
    }

    private func canvasFont() -> BrowserFont {
        let size: Double = Double(font.prefix(while: { $0.isNumber })) ?? 10
        return getFont(size: Int(size * 0.75), weight: "normal", style: "roman", family: "serif")
    }
}
