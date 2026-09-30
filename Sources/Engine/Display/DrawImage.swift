import CoreGraphics
struct DrawImage: DisplayCommand {
    let image: CGImage
    let rendering: ImageRendering
    var rect: Rect
    var parentEffect: BrowserVisualEffect?
    func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.drawImage(
            image,
            in: Rect(
                left: rect.left,
                top: rect.top - scroll,
                right: rect.right,
                bottom: rect.bottom - scroll
            ),
            rendering: rendering
        )
    }
}
