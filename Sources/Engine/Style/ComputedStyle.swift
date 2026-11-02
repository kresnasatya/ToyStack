// MARK: - ComputedStyle

struct ComputedStyle: Equatable {
    var layout: LayoutStyle
    var box: BoxStyle
    var text: TextStyle
    var visual: VisualStyle

    static let initial: ComputedStyle = ComputedStyle(
        layout: .initial,
        box: .initial,
        text: .initial,
        visual: .initial
    )

    static func inheriting(from parent: ComputedStyle?) -> ComputedStyle {
        var style: ComputedStyle = .initial
        if let parent {
            style.text = parent.text
        }
        return style
    }
}

// MARK: - Diff

extension ComputedStyle {
    func matches(_ other: ComputedStyle, for property: StyleProperty) -> Bool {
        switch property {
        case .display: return layout.display == other.layout.display
        case .position: return layout.position.kind == other.layout.position.kind
        case .overflow: return layout.overflow == other.layout.overflow
        case .zIndex: return layout.zIndex == other.layout.zIndex
        case .width: return box.size.width == other.box.size.width
        case .height: return box.size.height == other.box.size.height
        case .maxWidth: return box.size.maxWidth == other.box.size.maxWidth
        case .aspectRatio: return box.size.aspectRatio == other.box.size.aspectRatio
        case .marginTop: return box.spacing.margin.top == other.box.spacing.margin.top
        case .marginRight: return box.spacing.margin.right == other.box.spacing.margin.right
        case .marginBottom: return box.spacing.margin.bottom == other.box.spacing.margin.bottom
        case .marginLeft: return box.spacing.margin.left == other.box.spacing.margin.left
        case .paddingTop: return box.spacing.padding.top == other.box.spacing.padding.top
        case .paddingRight: return box.spacing.padding.right == other.box.spacing.padding.right
        case .paddingBottom: return box.spacing.padding.bottom == other.box.spacing.padding.bottom
        case .paddingLeft: return box.spacing.padding.left == other.box.spacing.padding.left
        case .left: return layout.position.left == other.layout.position.left
        case .top: return layout.position.top == other.layout.position.top
        case .zoom: return box.zoom == other.box.zoom
        case .borderWidth: return box.decoration.border.width == other.box.decoration.border.width
        case .borderStyle: return box.decoration.border.style == other.box.decoration.border.style
        case .borderColor: return box.decoration.border.color == other.box.decoration.border.color
        case .borderRadius: return box.decoration.border.radii == other.box.decoration.border.radii
        case .outlineWidth: return box.decoration.outline.width == other.box.decoration.outline.width
        case .outlineStyle: return box.decoration.outline.style == other.box.decoration.outline.style
        case .outlineColor: return box.decoration.outline.color == other.box.decoration.outline.color
        case .color: return text.color == other.text.color
        case .fontFamily: return text.font.family == other.text.font.family
        case .fontSize: return text.font.size == other.text.font.size
        case .fontStyle: return text.font.style == other.text.font.style
        case .fontWeight: return text.font.weight == other.text.font.weight
        case .whiteSpace: return text.whiteSpace == other.text.whiteSpace
        case .direction: return text.direction == other.text.direction
        case .backgroundColor: return visual.background.color == other.visual.background.color
        case .backgroundImage: return visual.background.image == other.visual.background.image
        case .backgroundSize: return visual.background.size == other.visual.background.size
        case .imageRendering: return visual.image.rendering == other.visual.image.rendering
        case .objectFit: return visual.image.fit == other.visual.image.fit
        case .opacity: return visual.effects.opacity == other.visual.effects.opacity
        case .mixBlendMode: return visual.effects.blendMode == other.visual.effects.blendMode
        case .transform: return visual.effects.translation == other.visual.effects.translation
        case .filter: return visual.effects.blurRadius == other.visual.effects.blurRadius
        }
    }

    func changed(from old: ComputedStyle) -> Set<StyleProperty> {
        var changed: Set<StyleProperty> = []
        for property in StyleProperty.allCases where !old.matches(self, for: property) {
            changed.insert(property)
        }
        return changed
    }
}

// MARK: - Animation bridge

extension ComputedStyle {
    func value(for property: StyleProperty) -> AnimatedValue? {
        switch property {
        case .opacity: return .number(visual.effects.opacity)
        case .width: return box.size.width.map(AnimatedValue.length)
        case .height: return box.size.height.map(AnimatedValue.length)
        case .backgroundColor:
            return visual.background.color.map(AnimatedValue.color)
        case .transform:
            return visual.effects.translation.map(AnimatedValue.transform)
        default:
            return nil
        }
    }

    @discardableResult
    mutating func set(_ value: AnimatedValue, for property: StyleProperty) -> Bool {
        let before: ComputedStyle = self
        switch (property, value) {
        case (.opacity, .number(let v)): visual.effects.opacity = v
        case (.width, .length(let v)): box.size.width = v
        case (.height, .length(let v)): box.size.height = v
        case (.fontSize, .length(let v)): text.font.size = v
        case (.backgroundColor, .color(let c)): visual.background.color = c
        case (.transform, .transform(let p)): visual.effects.translation = p
        default: return false
        }
        return !matches(before, for: property)
    }
}
