import CoreGraphics

final class ImageLayout: EmbedLayout {
    var imgHeight: CGFloat = 0
    override var inlineAscent: CGFloat { height }
    override var inlineDescent: CGFloat { 0 }

    static func displaySize(for el: Element) -> (width: Double, height: Double) {
        let intrinsicW: Double = el.image.map { Double($0.width) } ?? 0
        let intrinsicH: Double = el.image.map { Double($0.height) } ?? 0
        let aspect: Double = intrinsicH == 0 ? 1 : intrinsicW / intrinsicH
        let wAttr: Double? = el.attributes["width"].flatMap({ Double($0) })
        let hAttr: Double? = el.attributes["height"].flatMap({ Double($0) })
        if let w = wAttr, let h = hAttr { return (w, h) }
        else if let w = wAttr { return (w, w / aspect) }
        else if let h = hAttr { return (h * aspect, h) }
        return (intrinsicW, intrinsicH)
    }

    override func layout() {
        super.layout()
        guard let el = node as? Element else { return }
        let size: (width: Double, height: Double) = ImageLayout.displaySize(for: el)
        width = scaled(CGFloat(size.width))
        imgHeight = scaled(CGFloat(size.height))
        height = max(imgHeight, font.linespace)
    }

    override func paint() -> [any DisplayItem] {
        guard let image = (node as? Element)?.image else { return [] }
        let rect = Rect(left: x, top: y + height - imgHeight, right: x + width, bottom: y + height)
        return [DrawImage(image: image, rendering: ImageRendering(css: node.style["image-rendering"]), rect: rect, parentEffect: nil)]
    }
}
