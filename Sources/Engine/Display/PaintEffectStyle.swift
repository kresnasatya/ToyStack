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
func paintEffectStyle(node: DOMNode) -> PaintEffectStyle? {
    if node.animations.isEmpty,
        node.style["opacity"] == nil,
        node.style["mix-blend-mode"] == nil,
        node.style["transform"] == nil,
        node.style["filter"] == nil {
        return nil
    }
    let opacity: Double = Double(node.style["opacity"] ?? "1.0") ?? 1.0
    let blendMode: BrowserBlendMode? = browserBlendMode(node.style["mix-blend-mode"])
    let translation: CGPoint? = CSSValueParser.transform(node.style["transform"] ?? "")
    let blurRadius: CGFloat = CSSValueParser.blur(node.style["filter"] ?? "")
    let animated: Bool = node.animations.values.contains(where: { $0.animatedProperty == "transform" || $0.animatedProperty == "opacity" })

    guard blurRadius > 0 || opacity < 1
        || (blendMode != nil && blendMode != .normal)
        || translation != nil || animated
    else { return nil }

    return PaintEffectStyle(
        opacity: opacity,
        blendMode: blendMode,
        translation: translation,
        blurRadius: blurRadius
    )
}
