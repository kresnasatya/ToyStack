import CoreGraphics

// MARK: - DrawOutline
public struct DrawOutline: DisplayCommand {
    public var rect: Rect
    public let color: String
    public let thickness: CGFloat
    public var parentEffect: BrowserVisualEffect? = nil

    public init(rect: Rect, color: String, thickness: CGFloat) {
        self.rect = rect
        self.color = color
        self.thickness = thickness
    }

    public func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.strokeRect(
            Rect(left: rect.left, top: rect.top - scroll, right: rect.right, bottom: rect.bottom - scroll),
            color: BrowserColor(cssName: color),
            lineWidth: thickness
        )
    }

    public func shifted(dx: CGFloat, dy: CGFloat) -> any DisplayCommand {
        var copy: DrawOutline = self
        copy.rect = rect.translated(dx: dx, dy: dy)
        return copy
    }
}

extension DrawOutline {

    @MainActor
    static func fromStyle(_ node: any DOMNode, rect: Rect) -> DrawOutline? {
        let style: String = node.style["outline-style"] ?? "none"
        guard style != "none", style != "hidden" else { return nil }
        guard let thickness = CSSValueParser.outlineWidth(node.style["outline-width"] ?? "medium"),
            thickness > 0
        else { return nil }
        let color: String = node.style["outline-color"] ?? node.style["color"] ?? "black"
        return DrawOutline(rect: rect, color: color, thickness: thickness)
    }

    @MainActor
    static func fromBorderStyle(_ node: any DOMNode, rect: Rect) -> DrawOutline? {
        let style: String = node.style["border-style"] ?? "none"
        guard style != "none", style != "hidden" else { return nil }
        guard let thickness = CSSValueParser.outlineWidth(node.style["border-width"] ?? "medium"), thickness > 0 else { return nil }
        let color: String = node.style["border-color"] ?? "black"
        return DrawOutline(rect: rect, color: color, thickness: thickness)
    }
}
