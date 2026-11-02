import Foundation

// MARK: - StyleProperty

enum StyleProperty: CaseIterable, Hashable {
    case display, position, overflow, zIndex
    case width, height, maxWidth, aspectRatio
    case marginTop, marginRight, marginBottom, marginLeft
    case paddingTop, paddingRight, paddingBottom, paddingLeft
    case left, top, zoom
    case borderWidth, borderStyle, borderColor, borderRadius
    case outlineWidth, outlineStyle, outlineColor
    case color, fontFamily, fontSize, fontStyle, fontWeight, whiteSpace, direction
    case backgroundColor, backgroundImage, backgroundSize, imageRendering, objectFit
    case opacity, mixBlendMode, transform, filter

    init?(cssName: String) {
        switch cssName {
        case "display": self = .display
        case "position": self = .position
        case "overflow": self = .overflow
        case "z-index": self = .zIndex
        case "width": self = .width
        case "height": self = .height
        case "max-width": self = .maxWidth
        case "aspect-ratio": self = .aspectRatio
        case "margin-top": self = .marginTop
        case "margin-right": self = .marginRight
        case "margin-bottom": self = .marginBottom
        case "margin-left": self = .marginLeft
        case "padding-top": self = .paddingTop
        case "padding-right": self = .paddingRight
        case "padding-bottom": self = .paddingBottom
        case "padding-left": self = .paddingLeft
        case "left": self = .left
        case "top": self = .top
        case "zoom": self = .zoom
        case "border-width": self = .borderWidth
        case "border-style": self = .borderStyle
        case "border-color": self = .borderColor
        case "border-radius", "border-top-left-radius", "border-top-right-radius",
            "border-bottom-right-radius", "border-bottom-left-radius":
            self = .borderRadius
        case "outline-width": self = .outlineWidth
        case "outline-style": self = .outlineStyle
        case "outline-color": self = .outlineColor
        case "color": self = .color
        case "font-family": self = .fontFamily
        case "font-size": self = .fontSize
        case "font-style": self = .fontStyle
        case "font-weight": self = .fontWeight
        case "white-space": self = .whiteSpace
        case "direction": self = .direction
        case "background-color": self = .backgroundColor
        case "background-image": self = .backgroundImage
        case "background-size": self = .backgroundSize
        case "image-rendering": self = .imageRendering
        case "object-fit": self = .objectFit
        case "opacity": self = .opacity
        case "mix-blend-mode": self = .mixBlendMode
        case "transform": self = .transform
        case "filter": self = .filter
        default: return nil
        }
    }

    var cssName: String {
        switch self {
        case .display: return "display"
        case .position: return "position"
        case .overflow: return "overflow"
        case .zIndex: return "z-index"
        case .width: return "width"
        case .height: return "height"
        case .maxWidth: return "max-width"
        case .aspectRatio: return "aspect-ratio"
        case .marginTop: return "margin-top"
        case .marginRight: return "margin-right"
        case .marginBottom: return "margin-bottom"
        case .marginLeft: return "margin-left"
        case .paddingTop: return "padding-top"
        case .paddingRight: return "padding-right"
        case .paddingBottom: return "padding-bottom"
        case .paddingLeft: return "padding-left"
        case .left: return "left"
        case .top: return "top"
        case .zoom: return "zoom"
        case .borderWidth: return "border-width"
        case .borderStyle: return "border-style"
        case .borderColor: return "border-color"
        case .borderRadius: return "border-radius"
        case .outlineWidth: return "outline-width"
        case .outlineStyle: return "outline-style"
        case .outlineColor: return "outline-color"
        case .color: return "color"
        case .fontFamily: return "font-family"
        case .fontSize: return "font-size"
        case .fontStyle: return "font-style"
        case .fontWeight: return "font-weight"
        case .whiteSpace: return "white-space"
        case .direction: return "direction"
        case .backgroundColor: return "background-color"
        case .backgroundImage: return "background-image"
        case .backgroundSize: return "background-size"
        case .imageRendering: return "image-rendering"
        case .objectFit: return "object-fit"
        case .opacity: return "opacity"
        case .mixBlendMode: return "mix-blend-mode"
        case .transform: return "transform"
        case .filter: return "filter"
        }
    }
}

// MARK: - Property sets

extension StyleProperty {
    static let paintOnly: Set<StyleProperty> = [
        .color, .backgroundColor, .backgroundImage, .backgroundSize,
        .borderColor, .borderRadius,
        .outlineColor, .outlineStyle, .outlineWidth,
        .filter, .mixBlendMode, .opacity, .transform, .zIndex,
        .imageRendering, .objectFit,
    ]

    static let paintStyle: Set<StyleProperty> = [
        .backgroundColor, .backgroundImage, .backgroundSize,
        .borderColor, .borderStyle, .borderWidth, .borderRadius,
        .color, .filter, .imageRendering, .mixBlendMode,
        .objectFit, .opacity,
        .outlineColor, .outlineStyle, .outlineWidth,
        .transform, .zIndex,
    ]

    static let inherited: [StyleProperty] = [
        .color, .fontFamily, .fontSize, .fontStyle, .fontWeight, .whiteSpace, .direction,
    ]

    var affectsLayout: Bool {
        return !StyleProperty.paintOnly.contains(self)
    }
}
