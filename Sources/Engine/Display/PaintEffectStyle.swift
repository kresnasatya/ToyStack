import CoreGraphics

// MARK: - PaintEffectStyle

struct PaintEffectStyle {
    let opacity: Double
    let blendMode: BrowserBlendMode?
    let translation: CGPoint?
    let blurRadius: CGFloat
}

// MARK: - Resolution

@MainActor
func paintEffectStyle(node: DOMRef) -> PaintEffectStyle? {
    let effects: VisualStyle.Effects = node.style.computed.visual.effects
    let animated: Bool = node.animations[.property(.transform)] != nil
        || node.animations[.property(.opacity)] != nil

    guard effects.blurRadius > 0 || effects.opacity < 1
        || (effects.blendMode != nil && effects.blendMode != .normal)
        || effects.translation != nil || animated
    else { return nil }

    return PaintEffectStyle(
        opacity: effects.opacity,
        blendMode: effects.blendMode,
        translation: effects.translation,
        blurRadius: effects.blurRadius
    )
}
