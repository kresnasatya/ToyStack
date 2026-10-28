import CoreGraphics

@MainActor
final class ImageLayout: EmbedLayout {
    var imgHeight: CGFloat = 0

    override init(
        node: any DOMNode,
        parent: any LayoutObject,
        previous: (any LayoutObject)?
    ) {
        super.init(node: node, parent: parent, previous: previous)
        widthField.setDependencies([
            parent.widthField,
            zoomField,
            node.style.field("aspect-ratio"),
            node.style.field("max-width"),
        ])
        heightField.setDependencies([
            widthField,
            zoomField,
            fontField,
            node.style.field("aspect-ratio"),
        ])
    }

    static func displaySize(for el: Element, notify: any InvalidatableField) -> (width: Double, height: Double) {
        let intrinsicW: Double = el.image.map { Double($0.width) } ?? 0
        let intrinsicH: Double = el.image.map { Double($0.height) } ?? 0
        let ratio: AspectRatio? = AspectRatio(css: el.style.read("aspect-ratio", notify: notify)) ?? AspectRatio(intrinsicWidth: intrinsicW, intrinsicHeight: intrinsicH)
        let wAttr: Double? = el.attributes["width"].flatMap({ Double($0) })
        let hAttr: Double? = el.attributes["height"].flatMap({ Double($0) })
        if let w = wAttr, let h = hAttr { return (w, h) }
        else if let w = wAttr { return (w, ratio?.height(forWidth: w) ?? w) }
        else if let h = hAttr { return (ratio?.width(forHeight: h) ?? h, h) }
        return (intrinsicW, intrinsicH)
    }

    static func usedWidth(
        for el: Element,
        available: CGFloat,
        zoom: CGFloat,
        notify: any InvalidatableField
    ) -> CGFloat {
        let intrinsic: CGFloat = CGFloat(displaySize(for: el, notify: notify).width) * zoom
        guard let limit = lengthPx(el.style.read("max-width", notify: notify), available: available, zoom: zoom) else {
            return intrinsic
        }
        return min(intrinsic, limit)
    }

    static func usedHeight(for el: Element, usedWidth: CGFloat, zoom: CGFloat, notify: any InvalidatableField) -> CGFloat {
        let size: (width: Double, height: Double) = displaySize(for: el, notify: notify)
        let ratio: AspectRatio? = AspectRatio(css: el.style.read("aspect-ratio", notify: notify)) ?? AspectRatio(intrinsicWidth: size.width, intrinsicHeight: size.height)
        guard let height = ratio?.height(forWidth: Double(usedWidth / zoom)) else {
            return CGFloat(size.height) * zoom
        }
        return CGFloat(height) * zoom
    }

    override func layout() {
        if !layoutNeeded() { return }
        super.layout()
        guard let el = node as? Element else { return }
        let available: CGFloat = parent!.widthField.read(notify: widthField)
        let zoom: CGFloat = zoomField.read(notify: widthField)
        let usedWidth: CGFloat = ImageLayout.usedWidth(
            for: el,
            available: available,
            zoom: zoom,
            notify: widthField
        )
        widthField.set(usedWidth)
        imgHeight = ImageLayout.usedHeight(
            for: el,
            usedWidth: widthField.read(notify: heightField),
            zoom: zoomField.read(notify: heightField),
            notify: heightField
        )
        heightField.set(max(imgHeight, fontField.read(notify: heightField).linespace))
        setAscentFromHeight()
    }

    override func paint(into items: inout [any DisplayItem]) {
        guard let image = (node as? Element)?.image else { return }
        let box = Rect(left: x, top: y + height - imgHeight, right: x + width, bottom: y + height)
        let content: Rect = ObjectFit(
            box: box,
            intrinsicWidth: scaled(CGFloat(image.width)),
            intrinsicHeight: scaled(CGFloat(image.height)),
            css: node.style["object-fit"]
        ).contentRect
        items.append(DrawClippedImage(
            image: image,
            rendering: ImageRendering(css: node.style["image-rendering"]),
            rect: content,
            clip: box
        ))
    }
}
