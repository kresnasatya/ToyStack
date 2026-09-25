import CoreGraphics

// MARK: - DrawRRect
struct DrawRRect: DisplayCommand {
    var rect: Rect
    var parentEffect: BrowserVisualEffect?
    let radius: CGFloat
    let color: String

    func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.fillRRect(rect.cgRect, radius: radius, color: BrowserColor(cssName: color))
    }
}
