import CoreGraphics

struct LayerEffectStrategy: Sendable {
    enum Kind: Comparable {
        case flat
        case ca
        case blendFallback
        case scrollFallback
    }

    let kind: Kind
    let effect: LayerEffect?
    let blur: CGFloat

    init(kind: Kind, effect: LayerEffect?, blur: CGFloat) {
        self.kind = kind
        self.effect = effect
        self.blur = blur
    }
}

// MARK: - Resolution

extension LayerEffectStrategy {
    static func resolve(
        _ layer: RasterLayer,
        updates: [NodeID: EffectUpdate]
    ) -> LayerEffectStrategy {
        var kind: Kind = .flat
        var opacity: Double = 1
        var translation: CGPoint = CGPoint.zero
        var blur: CGFloat = 0
        var key: NodeID?
        var blendMode: BrowserBlendMode?
        var clipRect: Rect?
        for scope in layer.identity.ancestorChain {
            let update: EffectUpdate? = scope.placement.node.flatMap { updates[$0] }
            let animated: Bool = update?.isAnimatedTransform ?? scope.placement.animatedTransform
            switch scope.kind {
            case .scroll:
                kind = max(kind, .scrollFallback)
            case .blend(let scopeOpacity, let scopeMode):
                let updatedOpacity: Double = update?.style.opacity ?? scopeOpacity
                let updatedMode: BrowserBlendMode? = update.map({ $0.style.blendMode }) ?? scopeMode
                opacity *= updatedOpacity
                if let updatedMode, updatedMode != .normal {
                    if updatedMode.compositingFilterName != nil {
                        kind = max(kind, .ca)
                        if blendMode == nil { blendMode = updatedMode }
                    } else {
                        kind = max(kind, .blendFallback)
                    }
                } else if updatedOpacity < 1 {
                    kind = max(kind, .ca)
                }
                if key == nil { key = scope.placement.node }
            case .transform(let scopeTranslation):
                let updatedTranslation: CGPoint? = update.map({ $0.style.translation }) ?? scopeTranslation
                if let updatedTranslation {
                    translation.x += updatedTranslation.x
                    translation.y += updatedTranslation.y
                    kind = max(kind, .ca)
                }
                if animated { kind = max(kind, .ca) }
                if key == nil { key = scope.placement.node }
            case .blur(let scopeRadius):
                let updatedRadius: CGFloat = update?.style.blurRadius ?? scopeRadius
                if updatedRadius > 0 {
                    blur = max(blur, updatedRadius)
                    kind = max(kind, .ca)
                    if key == nil { key = scope.placement.node }
                }
            case .clip(let shape):
                let local: Rect = Rect(
                    left: shape.rect.left - translation.x,
                    top: shape.rect.top - translation.y,
                    right: shape.rect.right - translation.x,
                    bottom: shape.rect.bottom - translation.y
                )
                clipRect = clipRect.map({ $0.intersect(local) }) ?? local
            }
        }
        let effect: LayerEffect? = kind == .ca
            ? LayerEffect(
                key: key,
                opacity: opacity,
                translation: translation,
                blendMode: blendMode,
                clipRect: clipRect
            )
            : nil
        return LayerEffectStrategy(kind: kind, effect: effect, blur: blur)
    }

    static func updatesAreCA(_ updates: [NodeID: EffectUpdate]) -> Bool {
        return updates.values.allSatisfy({ update in
            update.style.blurRadius == 0
                && (update.style.blendMode == nil
                    || update.style.blendMode == .normal
                    || update.style.blendMode?.compositingFilterName != nil)
        })
    }
}
