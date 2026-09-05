import Engine
import SwiftUI

final class SwiftUIRenderer: Renderer {
    var context: GraphicsContext
    private var saved: [GraphicsContext] = []

    init(context: GraphicsContext) {
        self.context = context
    }

    func saveState() {
        saved.append(context)
    }

    func restoreState() {
        if let last = saved.popLast() {
            context = last
        }
    }

    func translateBy(x: CGFloat, y: CGFloat) {
        context.translateBy(x: x, y: y)
    }

    func clip(to rect: CGRect) {
        context.clip(to: Path(rect))
    }

    func fillRect(_ rect: CGRect, color: EngineColor) {
        context.fill(Path(rect), with: .color(Color(engine: color)))
    }

    func fillRRect(_ rect: CGRect, radius: CGFloat, color: EngineColor) {
        context.fill(
            Path(roundedRect: rect, cornerRadius: radius),
            with: .color(Color(engine: color))
        )
    }

    func strokeSegment(from: CGPoint, to: CGPoint, color: EngineColor, lineWidth: CGFloat) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(Color(engine: color)), lineWidth: lineWidth)
    }

    func strokeRect(_ rect: CGRect, color: EngineColor, lineWidth: CGFloat) {
        context.stroke(Path(rect), with: .color(Color(engine: color)), lineWidth: lineWidth)
    }

    func drawText(_ text: String, font: CTFont, color: EngineColor, at point: CGPoint) {
        let swiftText = Text(text)
            .font(Font(font))
            .foregroundColor(Color(engine: color))
        context.draw(swiftText, at: point, anchor: .topLeading)
    }

    func drawImage(_ image: CGImage, in rect: CGRect) {
        context.draw(Image(decorative: image, scale: 1), in: rect)
    }

    func drawLayer(_ options: LayerOptions, content: (any Renderer) -> Void) {
        var outer = context
        if let o = options.opacity {
            outer.opacity = o
        }
        if let m = options.blendMode {
            outer.blendMode = m.toSwiftUI
        }
        outer.drawLayer { inner in
            var inner = inner
            if let blur = options.blur {
                inner.addFilter(.blur(radius: blur))
            }
            content(SwiftUIRenderer(context: inner))
        }
        context = outer
    }
}

extension EngineBlendMode {
    var toSwiftUI: GraphicsContext.BlendMode {
        switch self {
            case .normal: return .normal
            case .multiply: return .multiply
            case .difference: return .difference
            case .destinationIn: return .destinationIn
        }
    }
}

extension Color {
    init(engine: EngineColor) {
        self = Color(
            .sRGB,
            red: engine.red,
            green: engine.green,
            blue: engine.blue,
            opacity: engine.alpha
        )
    }
}
