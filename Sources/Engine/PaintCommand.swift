import CoreGraphics

func cssColorToRGB(_ cssName: String) -> RGBColor? {
    let name = cssName.lowercased().trimmingCharacters(in: .whitespaces)
    if name.hasPrefix("#") {
        let hex = String(name.dropFirst())
        let expanded = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
        if expanded.count == 6,
            let r = UInt8(expanded.prefix(2), radix: 16),
            let g = UInt8(expanded.dropFirst(2).prefix(2), radix: 16),
            let b = UInt(expanded.dropFirst(4).prefix(2), radix: 16)
        {
            return (Double(r), Double(g), Double(b))
        }
    }

    switch name {
    case "white": return (255, 255, 255)
    case "black": return (0, 0, 0)
    case "red": return (255, 0, 0)
    case "blue": return (0, 0, 255)
    case "green": return (0, 128, 0)
    case "gray", "grey": return (128, 128, 128)
    case "orange": return (255, 165, 0)
    case "lightblue": return (173, 216, 230)
    case "lightgreen": return (144, 238, 144)
    case "steelblue": return (70, 130, 180)
    case "lightgray", "lightgrey": return (211, 211, 211)
    case "yellow": return (255, 255, 0)
    case "purple": return (128, 0, 128)
    case "salmon": return (250, 128, 114)
    case "whitesmoke": return (245, 245, 245)
    case "khaki": return (240, 230, 140)
    case "tomato": return (255, 99, 71)
    case "gold": return (255, 215, 0)
    case "orchid": return (218, 112, 214)
    default: return nil
    }
}

// MARK: - PaintCommand
public protocol PaintCommand {
    var rect: Rect { get }
    var parentEffect: VisualEffect? { get set }
    func execute(scroll: CGFloat, renderer: any Renderer)
}

// MARK: - DrawRect
public struct DrawRect: PaintCommand {
    public let rect: Rect
    public let color: String
    public var parentEffect: VisualEffect? = nil

    public init(rect: Rect, color: String) {
        self.rect = rect
        self.color = color
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        let r = CGRect(
            x: rect.left,
            y: rect.top - scroll,
            width: rect.right - rect.left,
            height: rect.bottom - rect.top
        )
        renderer.fillRect(r, color: EngineColor(cssName: color))
    }
}

// MARK: - DrawLine
public struct DrawLine: PaintCommand {
    public let rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: VisualEffect? = nil

    public init(
        x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: String, thickness: CGFloat
    ) {
        self.rect = Rect(left: x1, top: y1, right: x2, bottom: y2)
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.strokeSegment(
            from: CGPoint(x: rect.left, y: rect.top - scroll),
            to: CGPoint(x: rect.right, y: rect.bottom - scroll),
            color: EngineColor(cssName: color),
            lineWidth: thickness
        )
    }
}

// MARK: - DrawText
public struct DrawText: PaintCommand {
    public let rect: Rect
    public let text: String
    public let font: BrowserFont
    public let color: String
    public var parentEffect: VisualEffect? = nil

    public init(
        x1: CGFloat, y1: CGFloat, text: String, font: BrowserFont, color: String
    ) {
        self.rect = Rect(
            left: x1, top: y1, right: x1 + font.measure(text), bottom: y1 + font.linespace)
        self.text = text
        self.font = font
        self.color = color
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.drawText(text, font: font.ctFont, color: EngineColor(cssName: color), at: CGPoint(x: rect.left, y: rect.top - scroll))
    }
}

// MARK: - DrawOutline
public struct DrawOutline: PaintCommand {
    public let rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: VisualEffect? = nil

    public init(rect: Rect, color: String, thickness: CGFloat) {
        self.rect = rect
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        let r = CGRect(
            x: rect.left, y: rect.top - scroll, width: rect.right - rect.left,
            height: rect.bottom - rect.top)
        renderer.strokeRect(r, color: EngineColor(cssName: color), lineWidth: thickness)
    }
}

// MARK: - DrawCompositedLayer
struct DrawCompositedLayer: PaintCommand {
    var rect: Rect
    var parentEffect: VisualEffect?
    let layer: CompositedLayer

    init(layer: CompositedLayer) {
        self.layer = layer
        self.rect = layer.absoluteBounds()
    }

    func execute(scroll: CGFloat, renderer: any Renderer) {
        let bounds = layer.compositedBounds()
        if let image = layer.cachedImage {
            renderer.drawImage(image, in: bounds.cgRect)
        } else {
            renderer.saveState()
            renderer.translateBy(x: bounds.left, y: bounds.top)
            layer.raster(renderer: renderer)
            renderer.restoreState()
        }

    }
}

// MARK: - DrawRRect
struct DrawRRect: PaintCommand {
    var rect: Rect
    var parentEffect: VisualEffect?
    let radius: CGFloat
    let color: String

    func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.fillRRect(rect.cgRect, radius: radius, color: EngineColor(cssName: color))
    }
}
