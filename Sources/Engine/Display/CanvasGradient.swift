import CoreGraphics

// MARK: - CanvasGradient
struct CanvasGradient {
    let id: Int
    let kind: CanvasGradientKind
    private(set) var stops: [CanvasGradientStop] = []

    mutating func addStop(_ stop: CanvasGradientStop) {
        stops.append(stop)
    }

    func cgGradient() -> CGGradient? {
        let stops: [CanvasGradientStop] = self.stops
            .map { CanvasGradientStop(offset: max(0, min(1, $0.offset)), color: $0.color) }
            .sorted { $0.offset < $1.offset }
        guard stops.count >= 2 else { return nil }
        let colors: [CGColor] = stops.map { BrowserColor(cssName: $0.color).cgColor }
        let locations: [CGFloat] = stops.map { CGFloat($0.offset) }
        return CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: locations
        )
    }

    func draw(_ cgGradient: CGGradient, cg: CGContext) {
        switch kind {
            case .linear(let start, let end):
                cg.drawLinearGradient(cgGradient, start: start.cgPoint, end: end.cgPoint, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            case .radial(let start, let startRadius, let end, let endRadius):
                cg.drawRadialGradient(cgGradient, startCenter: start.cgPoint, startRadius: startRadius, endCenter: end.cgPoint, endRadius: endRadius, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
}

// MARK: - CanvasGradientKind
enum CanvasGradientKind {
    case linear(start: Point, end: Point)
    case radial(start: Point, startRadius: CGFloat, end: Point, endRadius: CGFloat)
}

// MARK: - CanvasGradientStop
struct CanvasGradientStop {
    let offset: Double
    let color: String
}
