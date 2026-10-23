import CoreGraphics
struct DrawImage: DisplayCommand {
    let image: CGImage
    let rendering: ImageRendering
    var rect: Rect
    var parentEffect: BrowserVisualEffect?
    let contentVersion: UInt64

    init(image: CGImage, rendering: ImageRendering, rect: Rect, parentEffect: BrowserVisualEffect?, contentVersion: UInt64 = 0) {
        self.image = image
        self.rendering = rendering
        self.rect = rect
        self.parentEffect = parentEffect
        self.contentVersion = contentVersion
    }

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

    func shifted(dx: CGFloat, dy: CGFloat) -> any DisplayCommand {
        var copy: DrawImage = self
        copy.rect = rect.translated(dx: dx, dy: dy)
        return copy
    }
}
