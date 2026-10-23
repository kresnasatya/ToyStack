import CoreGraphics

// MARK: - DrawRRect
struct DrawRRect: DisplayCommand {
    var rect: Rect
    var parentEffect: BrowserVisualEffect?
    let radii: CornerRadii
    let color: String

    func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.fillRRect(rect, radii: radii, color: BrowserColor(cssName: color))
    }

    func shifted(dx: CGFloat, dy: CGFloat) -> any DisplayCommand {
        var copy: DrawRRect = self
        copy.rect = rect.translated(dx: dx, dy: dy)
        return copy
    }
}
