import CoreGraphics

// MARK: - CanvasLayout
@MainActor
final class CanvasLayout: EmbedLayout {
    static let defaultWidthPx: CGFloat = 300
    static let defaultHeightPx: CGFloat = 150

    static func displayWidth(for el: Element) -> CGFloat {
        let attr: CGFloat = el.attributes["width"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? defaultWidthPx
        return attr
    }

    static func displayHeight(for el: Element) -> CGFloat {
        let attr: CGFloat = el.attributes["height"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? defaultHeightPx
        return attr
    }

    static func contentSize(for el: Element) -> (width: CGFloat, height: CGFloat) {
        return (CanvasLayout.displayWidth(for: el), CanvasLayout.displayHeight(for: el))
    }

    private var displayScale: CGFloat {
        (node as? Element)?.frame?.tab?.browser?.displayScale ?? 1
    }

    override func layout() {
        super.layout()
        guard let el = node as? Element else { return }
        let size: (width: CGFloat, height: CGFloat) = CanvasLayout.contentSize(for: el)

        self.width = scaled(size.width)
        self.height = scaled(size.height)
        el.canvasContext?.resize(width: size.width, height: size.height)
        el.canvasContext?.setScale(displayScale * zoom)
    }

    override func paint() -> [any DisplayItem] {
        guard let ctx = (node as? Element)?.canvasContext,
            let image: CGImage = ctx.image()
        else { return [] }
        return [
            DrawImage(
                image: image,
                rendering: .auto,
                rect: selfRect(),
                parentEffect: nil,
                contentVersion: ctx.revision
            )
        ]
    }
}
