import CoreGraphics

@MainActor
final class ImageLayout: EmbedLayout {
    var imgHeight: CGFloat = 0
    override var inlineAscent: CGFloat { height }
    override var inlineDescent: CGFloat { 0 }

    static func displaySize(for el: Element) -> (width: Double, height: Double) {
        let intrinsicW: Double = el.image.map { Double($0.width) } ?? 0
        let intrinsicH: Double = el.image.map { Double($0.height) } ?? 0
        let ratio: AspectRatio? = AspectRatio(css: el.style["aspect-ratio"]) ?? AspectRatio(intrinsicWidth: intrinsicW, intrinsicHeight: intrinsicH)
        let wAttr: Double? = el.attributes["width"].flatMap({ Double($0) })
        let hAttr: Double? = el.attributes["height"].flatMap({ Double($0) })
        if let w = wAttr, let h = hAttr { return (w, h) }
        else if let w = wAttr { return (w, ratio?.height(forWidth: w) ?? w) }
        else if let h = hAttr { return (ratio?.width(forHeight: h) ?? h, h) }
        return (intrinsicW, intrinsicH)
    }

    static func usedWidth(for el: Element, available: CGFloat, zoom: CGFloat) -> CGFloat {
        let intrinsic: CGFloat = CGFloat(displaySize(for: el).width) * zoom
        guard let limit = lengthPx(el.style["max-width"], available: available, zoom: zoom) else {
            return intrinsic
        }
        return min(intrinsic, limit)
    }

    static func usedHeight(for el: Element, usedWidth: CGFloat, zoom: CGFloat) -> CGFloat {
        let size: (width: Double, height: Double) = displaySize(for: el)
        let ratio: AspectRatio? = AspectRatio(css: el.style["aspect-ratio"]) ?? AspectRatio(intrinsicWidth: size.width, intrinsicHeight: size.height)
        guard let height = ratio?.height(forWidth: Double(usedWidth / zoom)) else {
            return CGFloat(size.height) * zoom
        }
        return CGFloat(height) * zoom
    }

    override func layout() {
        super.layout()
        guard let el = node as? Element else { return }
        let available: CGFloat = parent!.widthField.read(notify: widthField)
        let zoom: CGFloat = zoomField.read(notify: widthField)
        let usedWidth: CGFloat = ImageLayout.usedWidth(for: el, available: available, zoom: zoom)
        widthField.set(usedWidth)
        imgHeight = ImageLayout.usedHeight(for: el, usedWidth: usedWidth, zoom: zoom)
        height = max(imgHeight, font.linespace)
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
