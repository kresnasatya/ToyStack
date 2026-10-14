import CoreGraphics

// MARK: - DrawBackgroundImage
struct DrawBackgroundImage: DisplayCommand {
    let image: CGImage
    let rendering: ImageRendering
    let rect: Rect
    let clip: Rect
    var parentEffect: BrowserVisualEffect? = nil

    init(image: CGImage, rendering: ImageRendering, rect: Rect, clip: Rect) {
        self.image = image
        self.rendering = rendering
        self.rect = rect
        self.clip = clip
    }

    func execute(scroll: CGFloat, renderer: any Renderer) {
        renderer.saveState()
        renderer.clip(
            to: Rect(
                left: clip.left,
                top: clip.top - scroll,
                right: clip.right,
                bottom: clip.bottom - scroll
            )
        )
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
        renderer.restoreState()
    }
}
