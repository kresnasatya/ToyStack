import CoreGraphics

public enum EffectKind: Sendable {
    case blend(opacity: Double, mode: BrowserBlendMode?)
    case blur(radius: CGFloat)
    case clip(ClipShape)
    case transform(CGPoint?)
    case scroll(ClipShape, offset: CGFloat)

    var description: String {
        switch self {
        case .blend: return "blend"
        case .blur: return "blur"
        case .clip: return "clip"
        case .transform: return "transform"
        case .scroll: return "scroll"
        }
    }
}

func applyEffect(
    _ kind: EffectKind,
    renderer: any Renderer,
    content: (any Renderer) -> Void
) {
    switch kind {
    case .transform(let translation):
        renderer.saveState()
        if let translation {
            renderer.translateBy(x: translation.x, y: translation.y)
        }
        content(renderer)
        renderer.restoreState()
    case .clip(let shape):
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
        content(renderer)
        renderer.restoreState()
    case .scroll(let shape, let offset):
        renderer.saveState()
        renderer.clipRRect(shape.rect, radii: shape.radii)
        renderer.translateBy(x: 0, y: -offset)
        content(renderer)
        renderer.restoreState()
    case .blend(let opacity, let mode):
        guard opacity < 1.0 || mode != nil else {
            content(renderer)
            return
        }
        renderer.drawLayer(LayerOptions(opacity: opacity, blendMode: mode)) { inner in
            content(inner)
        }
    case .blur(let radius):
        renderer.drawLayer(LayerOptions(blur: radius)) { inner in
            content(inner)
        }
    }
}
