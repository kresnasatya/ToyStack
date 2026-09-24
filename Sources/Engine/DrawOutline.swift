import CoreGraphics

// MARK: - DrawOutline
public struct DrawOutline: DisplayCommand {
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
        let r: CGRect = CGRect(
            x: rect.left, y: rect.top - scroll, width: rect.right - rect.left,
            height: rect.bottom - rect.top)
        renderer.strokeRect(r, color: BrowserColor(cssName: color), lineWidth: thickness)
    }
}

extension DrawOutline {
    static func fromStyle(_ node: any DOMNode, rect: Rect) -> DrawOutline? {
        let style: String = node.style["outline-style"] ?? "none"
        guard style != "none", style != "hidden" else { return nil }
        guard let thickness = parseOutlineWidth(node.style["outline-width"] ?? "medium"),
            thickness > 0
        else { return nil }
        let color: String = node.style["outline-color"] ?? node.style["color"] ?? "black"
        return DrawOutline(rect: rect, color: color, thickness: thickness)
    }
}
