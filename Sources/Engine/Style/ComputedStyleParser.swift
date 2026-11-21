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

    private static let borderKeys: [(width: String, style: String, color: String)] = [
        ("border-top-width", "border-top-style", "border-top-color"),
        ("border-right-width", "border-right-style", "border-right-color"),
        ("border-bottom-width", "border-bottom-style", "border-bottom-color"),
        ("border-left-width", "border-left-style", "border-left-color"),
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
        let units: FontRelativeUnits = FontRelativeUnits(font: style.text.font)

        // MARK: Layout
        style.layout.display = LayoutStyle.Display(css: take("display"))
        style.layout.position = LayoutStyle.Positioning(
            kind: LayoutStyle.Position(css: take("position")),
            left: units.px(take("left")),
            top: units.px(take("top")),
            floating: LayoutStyle.Floating(
                side: LayoutStyle.FloatSide(css: take("float")),
                clear: LayoutStyle.ClearSide(css: take("clear"))
            )
        )
        style.layout.overflow = LayoutStyle.Overflow(css: take("overflow"))
        style.layout.zIndex = Int(take("z-index") ?? "0") ?? 0

        // MARK: Box
        style.box.size.width = units.px(take("width"))
        style.box.size.height = units.px(take("height"))
        style.box.size.boxSizing = BoxSizing(css: take("box-sizing"))
        let maxWidth: String? = take("max-width")
        style.box.size.constraints.maxWidth = units.px(maxWidth).map(Length.px) ?? Length(css: maxWidth)
        style.box.size.constraints.aspectRatio = AspectRatio(css: take("aspect-ratio"))
        style.box.spacing.margin = EdgeInsets(
            top: units.px(take("margin-top")) ?? 0,
            right: units.px(take("margin-right")) ?? 0,
            bottom: units.px(take("margin-bottom")) ?? 0,
            left: units.px(take("margin-left")) ?? 0
        )
        style.box.spacing.padding = EdgeInsets(
            top: max(0, units.px(take("padding-top")) ?? 0),
            right: max(0, units.px(take("padding-right")) ?? 0),
            bottom: max(0, units.px(take("padding-bottom")) ?? 0),
            left: max(0, units.px(take("padding-left")) ?? 0)
        )
        style.box.zoom = zoomFactor(take("zoom"))

        style.box.decoration.border.sides = BoxStyle.Decoration.Border.Sides(
            top: borderSide(borderKeys[0], take: take),
            right: borderSide(borderKeys[1], take: take),
            bottom: borderSide(borderKeys[2], take: take),
            left: borderSide(borderKeys[3], take: take)
        )
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

    private static func fontSize(_ raw: String, parent: ComputedStyle?) -> CGFloat? {
        let base: TextStyle.Font = parent?.text.font ?? TextStyle.initial.font
        if raw.hasSuffix("%"), let value = Double(raw.dropLast()) {
            return base.size * CGFloat(value) / 100
        }
        // CSS Values 4 §6.1.1: inside a font-* property, em, ex, and ch resolve
        // against the parent element's font.
        return FontRelativeUnits(font: base).px(raw)
    }

    private static func borderSide(
        _ keys: (width: String, style: String, color: String),
        take: (String) -> String?
    ) -> BoxStyle.Decoration.Border.Side {
        var side: BoxStyle.Decoration.Border.Side = .initial
        if let raw = take(keys.width) {
            side.width = CSSValueParser.outlineWidth(raw) ?? 0
        }
        side.style = BoxStyle.Decoration.LineStyle(css: take(keys.style))
        if let raw = take(keys.color) {
            side.color = BrowserColor.parse(raw) ?? BrowserColor(red: 0, green: 0, blue: 0)
        }
        return side
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
