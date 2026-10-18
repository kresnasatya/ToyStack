import CoreGraphics

// MARK: - PaintEffectStyle

struct PaintEffectStyle {
    let cornerRadii: CornerRadii
    let opacity: Double
    let blendMode: BrowserBlendMode?
    let translation: CGPoint?
    let blurRadius: CGFloat
}

// MARK: - Resolution

func paintEffectStyle(node: DOMNode) -> PaintEffectStyle? {
    let opacity: Double = Double(node.style["opacity"] ?? "1.0") ?? 1.0
    let blendMode: BrowserBlendMode? = browserBlendMode(node.style["mix-blend-mode"])
    let translation: CGPoint? = CSSValueParser.transform(node.style["transform"] ?? "")
    let cornerRadii: CornerRadii = CSSValueParser.cornerRadii(node.style["border-radius"]) ?? .zero
    let blurRadius: CGFloat = CSSValueParser.blur(node.style["filter"] ?? "")
    let animated: Bool = node.animations["transform"] != nil || node.animations["opacity"] != nil

    guard !cornerRadii.isZero || blurRadius > 0 || opacity < 1
        || (blendMode != nil && blendMode != .normal)
        || translation != nil || animated
    else { return nil }

    return PaintEffectStyle(
        cornerRadii: cornerRadii,
        opacity: opacity,
        blendMode: blendMode,
        translation: translation,
        blurRadius: blurRadius
    )
}
