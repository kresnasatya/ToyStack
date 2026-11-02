import CoreGraphics

// MARK: - IframeLayout
@MainActor
final class IframeLayout: EmbedLayout {
    static let defaultWidthPx: CGFloat = 300
    static let defaultHeightPx: CGFloat = 150

    var frame: Frame? { node.element?.frame }

    override init(
        node: DOMRef,
        parent: any LayoutObject,
        previous: (any LayoutObject)?
    ) {
        super.init(node: node, parent: parent, previous: previous)
        widthField.setDependencies([
            zoomField,
            node.style.field(.aspectRatio),
        ])
        heightField.setDependencies([
            zoomField,
            node.style.field(.aspectRatio),
        ])
    }

    static func displaySize(
        for el: ElementRef,
        notify: any InvalidatableField
    ) -> (width: CGFloat, height: CGFloat) {
        el.style.field(.aspectRatio).touch(notify)
        let ratio: AspectRatio? = el.style.computed.box.size.aspectRatio
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
        guard let el = node.element else { return }

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
        let computed: ComputedStyle = node.style.computed
        guard let bgColor: BrowserColor = computed.visual.background.color else { return }
        let radii: CornerRadii = computed.box.decoration.border.radii
        items.append(.rrect(rect: selfRect(), radii: radii, color: bgColor))
    }

}
