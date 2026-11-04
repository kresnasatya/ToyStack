import CoreGraphics

// MARK: - ComputedStyleParser

enum ComputedStyleParser {
    private static let radiusKeys: [String] = [
        "border-radius",
        "border-top-left-radius",
        "border-top-right-radius",
        "border-bottom-right-radius",
        "border-bottom-left-radius",
    ]

    static func parse(
        _ css: [String: String],
        parent: ComputedStyle?
    ) -> (style: ComputedStyle, unknown: [String: String]) {
        var unknown: [String: String] = css
        func take(_ key: String) -> String? {
            return unknown.removeValue(forKey: key)
        }

        var style: ComputedStyle = ComputedStyle.inheriting(from: parent)

        // MARK: Layout
        style.layout.display = LayoutStyle.Display(css: take("display"))
        style.layout.position = LayoutStyle.Positioning(
            kind: LayoutStyle.Position(css: take("position")),
            left: px(take("left")),
            top: px(take("top"))
        )
        style.layout.overflow = LayoutStyle.Overflow(css: take("overflow"))
        style.layout.zIndex = Int(take("z-index") ?? "0") ?? 0

        // MARK: Box
        style.box.size.width = px(take("width"))
        style.box.size.height = px(take("height"))
        style.box.size.maxWidth = Length(css: take("max-width"))
        style.box.size.aspectRatio = AspectRatio(css: take("aspect-ratio"))
        style.box.spacing.margin = EdgeInsets(
            top: px(take("margin-top")) ?? 0,
            right: px(take("margin-right")) ?? 0,
            bottom: px(take("margin-bottom")) ?? 0,
            left: px(take("margin-left")) ?? 0
        )
        style.box.spacing.padding = EdgeInsets(
            top: max(0, px(take("padding-top")) ?? 0),
            right: max(0, px(take("padding-right")) ?? 0),
            bottom: max(0, px(take("padding-bottom")) ?? 0),
            left: max(0, px(take("padding-left")) ?? 0)
        )
        style.box.zoom = zoomFactor(take("zoom"))

        let borderWidth: String? = take("border-width")
        style.box.decoration.border.width = borderWidth == nil
            ? 3
            : CSSValueParser.outlineWidth(borderWidth!) ?? 0
        style.box.decoration.border.style = BoxStyle.Decoration.LineStyle(css: take("border-style"))
        if let raw = take("border-color") {
            style.box.decoration.border.color = BrowserColor.parse(raw) ?? BrowserColor(red: 0, green: 0, blue: 0)
        }
        style.box.decoration.border.radii = CSSValueParser.cornerRadii(css) ?? .zero
        for key in radiusKeys {
            unknown.removeValue(forKey: key)
        }

        let outlineWidth: String? = take("outline-width")
        style.box.decoration.outline.width = outlineWidth == nil
            ? 3
            : CSSValueParser.outlineWidth(outlineWidth!) ?? 0
        style.box.decoration.outline.style = BoxStyle.Decoration.LineStyle(css: take("outline-style"))
        if let raw = take("outline-color") {
            style.box.decoration.outline.color = BrowserColor.parse(raw)
        }

        // MARK: Text
        if let raw = take("color") {
            style.text.color = BrowserColor.parse(raw) ?? BrowserColor(red: 0, green: 0, blue: 0)
        }
        if let raw = take("font-family") {
            style.text.font.family = raw
        }
        if let raw = take("font-size"), let size = fontSize(raw, parent: parent) {
            style.text.font.size = size
        }
        if let raw = take("font-style") {
            style.text.font.style = TextStyle.Style(css: raw)
        }
        if let raw = take("font-weight") {
            style.text.font.weight = TextStyle.Weight(css: raw)
        }
        if let raw = take("white-space") {
            style.text.whiteSpace = WhiteSpaceMode(cssValue: raw)
        }
        if let raw = take("direction") {
            style.text.direction = TextDirection(cssValue: raw)
        }

        // MARK: Visual
        if let raw = take("background-color"), raw.lowercased() != "transparent" {
            style.visual.background.color = BrowserColor.parse(raw)
        }
        if let raw = take("background-image"), raw.lowercased() != "none" {
            style.visual.background.image = CSSValueParser.backgroundImageURL(raw)
        }
        if let raw = take("background-size") {
            style.visual.background.size = BackgroundSizeSpec(css: raw) ?? .auto
        }
        if let raw = take("image-rendering") {
            style.visual.image.rendering = ImageRendering(css: raw)
        }
        if let raw = take("object-fit") {
            style.visual.image.fit = ObjectFitKind(css: raw)
        }
        if let raw = take("opacity") {
            style.visual.effects.opacity = Double(raw) ?? 1
        }
        style.visual.effects.blendMode = browserBlendMode(take("mix-blend-mode"))
        if let raw = take("filter") {
            style.visual.effects.blurRadius = CSSValueParser.blur(raw)
        }
        if let raw = take("transform") {
            style.visual.effects.translation = CSSValueParser.transform(raw)
        }

        return (style, unknown)
    }

    static func parseText(
        _ css: [String: String],
        parent: ComputedStyle?
    ) -> TextStyle {
        var text: TextStyle = parent?.text ?? .initial
        if let raw = css["color"] {
            text.color = BrowserColor.parse(raw) ?? BrowserColor(red: 0, green: 0, blue: 0)
        }
        if let raw = css["font-family"] {
            text.font.family = raw
        }
        if let raw = css["font-size"], let size = fontSize(raw, parent: parent) {
            text.font.size = size
        }
        if let raw = css["font-style"] {
            text.font.style = TextStyle.Style(css: raw)
        }
        if let raw = css["font-weight"] {
            text.font.weight = TextStyle.Weight(css: raw)
        }
        if let raw = css["white-space"] {
            text.whiteSpace = WhiteSpaceMode(cssValue: raw)
        }
        if let raw = css["direction"] {
            text.direction = TextDirection(cssValue: raw)
        }
        return text
    }

    // MARK: - Value helpers

    private static func px(_ raw: String?) -> CGFloat? {
        guard let raw, raw.hasSuffix("px"), let value = Double(raw.dropLast(2)) else { return nil }
        return CGFloat(value)
    }

    private static func fontSize(_ raw: String, parent: ComputedStyle?) -> CGFloat? {
        let base: CGFloat = parent?.text.font.size ?? TextStyle.initial.font.size
        if raw.hasSuffix("%"), let value = Double(raw.dropLast()) {
            return base * CGFloat(value) / 100
        }
        if raw.hasSuffix("px"), let value = Double(raw.dropLast(2)) {
            return CGFloat(value)
        }
        return nil
    }

    private static func zoomFactor(_ raw: String?) -> CGFloat? {
        guard let raw else { return nil }
        let trimmed: String = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("%"), let value = Double(trimmed.dropLast()) {
            return CGFloat(value / 100)
        }
        guard let value = Double(trimmed) else { return nil }
        return CGFloat(value)
    }
}
