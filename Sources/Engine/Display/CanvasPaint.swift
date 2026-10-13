import CoreGraphics

// MARK: - CanvasPaint
enum CanvasPaint {
    case color(String)
    case gradient(CanvasGradient)
}

let gradientMarker: String = "--gradient--"

extension CanvasPaint {
    var serialized: String {
        switch self {
            case .color(let value): return value
            case .gradient(let gradient): return "\(gradientMarker)\(gradient.id)"
        }
    }

    var isOpaque: Bool {
        switch self {
            case .color(let value): return value != "transparent"
            case .gradient: return true
        }
    }

    var solidColor: String {
        switch self {
            case .color(let value): return value
            case .gradient(let gradient): return gradient.stops.first?.color ?? "black"
        }
    }

    func fill(_ path: CGPath, cg: CGContext) {
        switch self {
            case .color(let value):
                cg.saveGState()
                cg.setFillColor(BrowserColor(cssName: value).cgColor)
                cg.addPath(path)
                cg.fillPath()
                cg.restoreGState()
            case .gradient(let gradient):
                guard let cgGradient: CGGradient = gradient.cgGradient() else { return }
                cg.saveGState()
                cg.addPath(path)
                cg.clip()
                gradient.draw(cgGradient, cg: cg)
                cg.restoreGState()
        }
    }

    func stroke(_ path: CGPath, width: CGFloat, cg: CGContext) {
        switch self {
            case .color(let value):
                cg.saveGState()
                cg.setStrokeColor(BrowserColor(cssName: value).cgColor)
                cg.setLineWidth(width)
                cg.addPath(path)
                cg.strokePath()
                cg.restoreGState()
            case .gradient(let gradient):
                guard let cgGradient: CGGradient = gradient.cgGradient() else { return }
                cg.saveGState()
                cg.setLineWidth(width)
                cg.addPath(path)
                cg.replacePathWithStrokedPath()
                cg.clip()
                gradient.draw(cgGradient, cg: cg)
                cg.restoreGState()
        }
    }
}
