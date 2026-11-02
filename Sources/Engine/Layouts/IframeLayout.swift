import CoreGraphics

// MARK: - IframeLayout
@MainActor
final class IframeLayout: EmbedLayout {
    static let defaultWidthPx: CGFloat = 300
    static let defaultHeightPx: CGFloat = 150

    var frame: Frame? { (node as? Element)?.frame }

    override init(
        node: any DOMNode,
        parent: any LayoutObject,
        previous: (any LayoutObject)?
    ) {
        super.init(node: node, parent: parent, previous: previous)
        widthField.setDependencies([
            zoomField,
            node.style.field("aspect-ratio"),
        ])
        heightField.setDependencies([
            zoomField,
            node.style.field("aspect-ratio"),
        ])
    }

    static func displaySize(
        for el: Element,
        notify: any InvalidatableField
    ) -> (width: CGFloat, height: CGFloat) {
        let ratio: AspectRatio? = AspectRatio(css: el.style.read("aspect-ratio", notify: notify))
        let widthAttr: Double? = el.attributes["width"].flatMap({ Double($0) })
        let heightAttr: Double? = el.attributes["height"].flatMap({ Double($0) })
        let content: (width: Double, height: Double)
        if let w = widthAttr, let h = heightAttr {
            content = (w, h)
        } else if let w = widthAttr {
            content = (w, ratio?.height(forWidth: w) ?? Double(defaultHeightPx))
        } else if let h = heightAttr {
            content = (ratio?.width(forHeight: h) ?? Double(defaultWidthPx), h)
        } else if let ratio {
            content = (Double(defaultWidthPx), ratio.height(forWidth: Double(defaultWidthPx)))
        } else {
            content = (Double(defaultWidthPx), Double(defaultHeightPx))
        }
        return (CGFloat(content.width) + 2, CGFloat(content.height) + 2)
    }

    override func layout() {
        if !layoutNeeded() { return }
        let sizeDirty: Bool = fields.isDirty(.width) || fields.isDirty(.height)
            || fields.isDirty(.zoom) || fields.isDirty(.font)
        super.layout()
        guard sizeDirty else { return }
        guard let el = node as? Element else { return }

        let size: (width: CGFloat, height: CGFloat) = IframeLayout.displaySize(for: el, notify: widthField)
        widthField.set(size.width * zoomField.read(notify: widthField))
        heightField.set(size.height * zoomField.read(notify: heightField))
        setAscentFromHeight()

        guard let frame, frame.loaded else { return }
        let innerWidth: CGFloat = widthField.get() - scaled(2)
        let innerHeight: CGFloat = heightField.get() - scaled(2)
        if frame.frameWidth != innerWidth {
            frame.frameWidth = innerWidth
            frame.frameHeight = innerHeight
            frame.setNeedsRender()
        } else if frame.frameHeight != innerHeight {
            frame.frameHeight = innerHeight
            frame.setNeedsLayout()
        }
    }

    override func paint(into items: inout [DisplayOp]) {
        let bgColor: String = node.style["background-color"] ?? "transparent"
        guard bgColor != "transparent" else { return }
        let radii: CornerRadii = CSSValueParser.cornerRadii(node.style) ?? .zero
        items.append(.rrect(rect: selfRect(), radii: radii, color: BrowserColor(cssName: bgColor)))
    }

}
