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

    override init(
        node: any DOMNode,
        parent: any LayoutObject,
        previous: (any LayoutObject)?
    ) {
        super.init(node: node, parent: parent, previous: previous)
        widthField.setDependencies([zoomField])
        heightField.setDependencies([zoomField])
    }

    override func layout() {
        if !layoutNeeded() { return }
        let sizeDirty: Bool = widthField.dirty || heightField.dirty || zoomField.dirty || fontField.dirty
        super.layout()
        guard sizeDirty else { return }
        guard let el = node as? Element else { return }
        let size: (width: CGFloat, height: CGFloat) = CanvasLayout.contentSize(for: el)

        widthField.set(size.width * zoomField.read(notify: widthField))
        heightField.set(size.height * zoomField.read(notify: heightField))
        setAscentFromHeight()

        el.canvasContext?.resize(width: size.width, height: size.height)
        el.canvasContext?.setScale(displayScale * pageZoom * zoomField.get())
    }

    override func paint(into items: inout [any DisplayItem]) {
        guard let ctx = (node as? Element)?.canvasContext,
            let image: CGImage = ctx.image()
        else { return }
        items.append(DrawImage(
            image: image,
            rendering: .auto,
            rect: selfRect(),
            parentEffect: nil,
            contentVersion: ctx.revision
        ))
    }
}
