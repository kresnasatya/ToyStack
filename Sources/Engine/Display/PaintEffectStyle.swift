import CoreGraphics

// MARK: - PaintEffectStyle

struct PaintEffectStyle: Sendable {
    let opacity: Double
    let blendMode: BrowserBlendMode?
    let translation: CGPoint?
    let blurRadius: CGFloat
}

// MARK: - Resolution

func paintEffectStyle(_ style: ComputedStyle, animated: Bool) -> PaintEffectStyle? {
    let effects: VisualStyle.Effects = style.visual.effects

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
