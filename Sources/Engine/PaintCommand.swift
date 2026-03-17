import SwiftUI

// MARK: - Color Parsing
// CSS color names used in browser.css and inline styles.
// Extend this as you encounter more colors in the browser stylesheet.
extension Color {
    init(cssName: String) {
        switch cssName.lowercased() {
        case "white": self = .white
        case "black": self = .black
        case "red": self = .red
        case "blue": self = .blue
        case "green": self = .green
        case "gray", "grey": self = .gray
        case "orange": self = .orange
        case "lightblue": self = Color(red: 0.68, green: 0.85, blue: 0.90)
        case "lightgray", "lightgrey": self = Color(red: 0.83, green: 0.83, blue: 0.85)
        case "transparent": self = .clear
        case "yellow": self = .yellow
        default: self = .black
        }
    }
}

// MARK: - PaintCommand Protocol
// Every draw command stores a bounding rect (for visibility culling)
// and can execute itself into SwiftUI GraphicsContext.
public protocol PaintCommand {
    var rect: Rect { get }
    func execute(scroll: CGFloat, context: inout GraphicsContext)
}

// MARK: - DrawRect
// Draws a filled rectangle with no border. Used for element backgrounds.
struct DrawRect: PaintCommand {
    let rect: Rect
    let color: String

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

    // DrawLine stores its endpoints in a Rect for uniform culling in Tab.draw()
    init(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, color: String, thickness: CGFloat) {
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

    init(x1: CGFloat, y1: CGFloat, text: String, font: BrowserFont, color: String) {
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

    func execute(scroll: CGFloat, context: inout GraphicsContext) {
        let r = CGRect(
            x: rect.left, y: rect.top - scroll, width: rect.right - rect.left,
            height: rect.bottom - rect.top)
        context.stroke(Path(r), with: .color(Color(cssName: color)), lineWidth: thickness)
    }
}
