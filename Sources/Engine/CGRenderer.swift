import CoreGraphics
import CoreText
import CoreImage

final class CGRenderer: Renderer {
    private let cg: CGContext
    private let canvasSize: CGSize
    private let scale: CGFloat
    private static let ciContext = CIContext(options: nil)

    init(cg: CGContext, canvasSize: CGSize, scale: CGFloat = 1) {
        self.cg = cg
        self.canvasSize = canvasSize
        self.scale = scale
    }

    static func renderBitmap(width: CGFloat, height: CGFloat, scale: CGFloat, backgroundColor: EngineColor? = nil, _ context: (CGRenderer) -> Void) -> CGImage? {
        let pxW = Int(width * scale), pxH = Int(height * scale)
        guard pxW > 0, pxH > 0,
            let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: height)
        ctx.scaleBy(x: 1, y: -1)

        let r = CGRenderer(cg: ctx, canvasSize: CGSize(width: width, height: height), scale: scale)
        if let bg = backgroundColor {
            r.fillRect(CGRect(x: 0, y: 0, width: width, height: height), color: bg)
        }
        context(r)
        return ctx.makeImage()
    }

    func saveState() { cg.saveGState() }
    func restoreState() { cg.restoreGState() }
    func translateBy(x: CGFloat, y: CGFloat) { cg.translateBy(x: x, y: y) }
    func clip(to rect: CGRect) { cg.clip(to: rect) }

    func fillRect(_ rect: CGRect, color: EngineColor) {
        cg.setFillColor(color.cgColor)
        cg.fill(rect)
    }

    func fillRRect(_ rect: CGRect, radius: CGFloat, color: EngineColor) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }

    func strokeSegment(from: CGPoint, to: CGPoint, color: EngineColor, lineWidth: CGFloat) {
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(lineWidth)
        cg.move(to: from)
        cg.addLine(to: to)
        cg.strokePath()
    }

    func strokeRect(_ rect: CGRect, color: EngineColor, lineWidth: CGFloat) {
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(lineWidth)
        cg.stroke(rect)
    }

    func drawText(_ text: String, font: CTFont, color: EngineColor, at point: CGPoint) {
        let attrs = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attrs)
        cg.saveGState()
        cg.translateBy(x: point.x, y: point.y + CTFontGetAscent(font))
        cg.scaleBy(x: 1, y: -1)
        cg.textMatrix = .identity
        cg.textPosition = .zero
        cg.setFillColor(color.cgColor)
        CTLineDraw(line, cg)
        cg.restoreGState()
    }

    func drawImage(_ image: CGImage, in rect: CGRect) {
        cg.saveGState()
        cg.translateBy(x: rect.minX, y: rect.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.draw(image, in: CGRect(x: 0, y:0, width: rect.width, height: rect.height))
        cg.restoreGState()
    }

    func drawLayer(_ options: LayerOptions, content: (any Renderer) -> Void) {
        if let blur = options.blur, blur > 0 {
            guard let layerImage = Self.renderBitmap(width: canvasSize.width, height: canvasSize.height, scale: scale, backgroundColor: nil, content)
                else { return }
            var ci = CIImage(cgImage: layerImage)
            let extent = ci.extent
            ci = ci.clampedToExtent()
            ci = ci.applyingGaussianBlur(sigma: blur / 2)
            ci = ci.cropped(to: extent)
            guard let blurred = Self.ciContext.createCGImage(ci, from: extent) else { return }
            drawImage(blurred, in: CGRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height))
        } else {
            cg.saveGState()
            if let o = options.opacity { cg.setAlpha(CGFloat(o)) }
            if let m = options.blendMode { cg.setBlendMode(m.toCG) }
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            content(self)
            cg.endTransparencyLayer()
            cg.restoreGState()
        }
    }
}

extension EngineColor {
    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension EngineBlendMode {
    var toCG: CGBlendMode {
        switch self {
            case .normal: return .normal
            case .multiply: return .multiply
            case.difference: return .difference
            case .destinationIn: return .destinationIn
        }
    }
}
