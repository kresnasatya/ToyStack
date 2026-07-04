import SwiftUI

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
    default: return nil
    }
}

// MARK: - Color Parsing
// CSS color names used in browser.css and inline styles.
// Extend this as you encounter more colors in the browser stylesheet.
extension Color {
    init(cssName: String) {
        let name = cssName.lowercased().trimmingCharacters(in: .whitespaces)
        // Hex color: #rgb or #rrggbb
        if name.hasPrefix("#") {
            let hex = String(name.dropFirst())
            let expanded =
                hex.count == 3
                ? hex.map({
                    "\($0)\($0)"
                }).joined() : hex
            if expanded.count == 6,
                let r = UInt8(expanded.prefix(2), radix: 16),
                let g = UInt8(expanded.dropFirst(2).prefix(2), radix: 16),
                let b = UInt8(expanded.dropFirst(4).prefix(2), radix: 16)
            {
                self = Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
                return
            }
        }
        switch cssName.lowercased() {
        case "white": self = .white
        case "black": self = .black
        case "red": self = .red
        case "blue": self = .blue
        case "green": self = .green
        case "gray", "grey": self = .gray
        case "orange": self = .orange
        case "lightblue": self = Color(red: 0.68, green: 0.85, blue: 0.90)
        case "lightgreen": self = Color(red: 0.56, green: 0.93, blue: 0.56)
        case "steelblue": self = Color(red: 0.27, green: 0.51, blue: 0.71)
        case "lightgray", "lightgrey": self = Color(red: 0.83, green: 0.83, blue: 0.83)
        case "transparent": self = .clear
        case "yellow": self = .yellow
        case "purple": self = .purple
        case "salmon": self = Color(red: 0.98, green: 0.50, blue: 0.45)
        case "whitesmoke": self = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
        case "khaki": self = Color(red: 240 / 255, green: 230 / 255, blue: 140 / 255)
        default: self = .black
        }
    }
}

// MARK: - PaintCommand Protocol
// Every draw command stores a bounding rect (for visibility culling)
// and can execute itself into SwiftUI GraphicsContext.
public protocol PaintCommand {
    var rect: Rect { get }
    var parentEffect: VisualEffect? { get set }
    func execute(scroll: CGFloat, context: inout GraphicsContext)
}

// MARK: - DrawRect
// Draws a filled rectangle with no border. Used for element backgrounds.
struct DrawRect: PaintCommand {
    let rect: Rect
    let color: String
    var parentEffect: VisualEffect? = nil

    init(rect: Rect, color: String) {
        self.rect = rect
        self.color = color
    }

    func execute(scroll: CGFloat, context: inout GraphicsContext) {
        // Shift the rectangle up by the scroll offfset to simulate scrolling.
        let r = CGRect(
            x: rect.left,
            y: rect.top - scroll,
            width: rect.right - rect.left,
            height: rect.bottom - rect.top
        )
        context.fill(Path(r), with: .color(Color(cssName: color)))
    }
}

// MARK: - DrawLine
// Draws a straight line. Used for the blinking cursor inside <input>.
struct DrawLine: PaintCommand {
    let rect: Rect  // rect.left/top = start point, right/bottom = end point
    let color: String
    let thickness: CGFloat
    var parentEffect: VisualEffect? = nil

    // DrawLine stores its endpoints in a Rect for uniform culling in Tab.draw()
    init(
        x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: String, thickness: CGFloat
    ) {
        self.rect = Rect(left: x1, top: y1, right: x2, bottom: y2)
        self.color = color
        self.thickness = thickness
    }

    func execute(scroll: CGFloat, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: rect.left, y: rect.top - scroll))
        path.addLine(to: CGPoint(x: rect.right, y: rect.bottom - scroll))
        context.stroke(path, with: .color(Color(cssName: color)), lineWidth: thickness)
    }
}

// MARK: - DrawText
// Draws a single string at position (x1, y1) using top-left as the anchor.
struct DrawText: PaintCommand {
    let rect: Rect  // bounding box of the rendered text
    let text: String
    let font: BrowserFont
    let color: String
    var parentEffect: VisualEffect? = nil

    init(
        x1: CGFloat, y1: CGFloat, text: String, font: BrowserFont, color: String
    ) {
        self.rect = Rect(
            left: x1, top: y1, right: x1 + font.measure(text), bottom: y1 + font.linespace)
        self.text = text
        self.font = font
        self.color = color
    }

    func execute(scroll: CGFloat, context: inout GraphicsContext) {
        let swiftText = Text(text)
            .font(Font(font.ctFont))
            .foregroundColor(Color(cssName: color))
        // Draw with the top-left corner at (x, y - scroll), matching Python's anchor="nw".
        context.draw(
            swiftText, at: CGPoint(x: rect.left, y: rect.top - scroll), anchor: .topLeading)
    }
}

// MARK: - DrawOutline
// Draws a rectangle border (no fill). Used for buttons and input boxes.
struct DrawOutline: PaintCommand {
    let rect: Rect
    let color: String
    let thickness: CGFloat
    var parentEffect: VisualEffect? = nil

    func execute(scroll: CGFloat, context: inout GraphicsContext) {
        let r = CGRect(
            x: rect.left, y: rect.top - scroll, width: rect.right - rect.left,
            height: rect.bottom - rect.top)
        context.stroke(Path(r), with: .color(Color(cssName: color)), lineWidth: thickness)
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

    func execute(scroll: CGFloat, context: inout GraphicsContext) {
        let bounds = layer.compositedBounds()
        if let image = layer.cachedImage {
            context.draw(Image(decorative: image, scale: 1), in: bounds.cgRect)
        } else {
            var ctx = context
            ctx.translateBy(x: bounds.left, y: bounds.top)
            layer.raster(context: &ctx)
        }

    }
}

// MARK: - DrawRRect
struct DrawRRect: PaintCommand {
    var rect: Rect
    var parentEffect: VisualEffect?
    let radius: CGFloat
    let color: String

    func execute(scroll: CGFloat, context: inout GraphicsContext) {
        let path = Path(roundedRect: rect.cgRect, cornerRadius: radius)
        context.fill(path, with: .color(Color(cssName: color)))
    }
}
