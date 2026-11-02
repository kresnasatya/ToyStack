import CoreGraphics

// MARK: - IframeLayout
@MainActor
final class IframeLayout: EmbedLayout {
    static let defaultWidthPx: CGFloat = 300
    static let defaultHeightPx: CGFloat = 150

    private var frame: Frame? { (node as? Element)?.frame }

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

    override func paintEffects(into items: inout [DisplayOp], from start: Int, session: inout PaintSession) {
        let rect: Rect = selfRect()
        let diff: CGFloat = scaled(1)
        let scroll: CGFloat = (frame?.loaded ?? false) ? (frame?.scroll ?? 0) : 0

        let innerRect: Rect = Rect(
            left: x + diff,
            top: y + diff,
            right: x + self.width - diff,
            bottom: y + self.height - diff
        )

        let clipRect: Rect = Rect(
            left: 0,
            top: scroll,
            right: innerRect.right - innerRect.left,
            bottom: scroll + (innerRect.bottom - innerRect.top)
        )

        let produced: [DisplayOp] = Array(items[start...])
        let clipShape: ClipShape = ClipShape(rect: clipRect, radii: .zero)
        let clipScope: EffectScope = session.makeScope(
            .clip(clipShape),
            node: nil,
            animatedTransform: false
        ).placed(rect: innerRect)
        let clip: DisplayEffect = DisplayEffect(scope: clipScope, children: produced)

        let transformScope: EffectScope = session.makeScope(
            .transform(CGPoint(x: x + diff, y: y + diff - scroll)),
            node: NodeKey(node),
            animatedTransform: false
        ).placed(rect: rect)
        let transform: DisplayEffect = DisplayEffect(
            scope: transformScope,
            children: [.effect(clip)]
        )

        var clipChildren: [DisplayOp] = [.effect(transform)]
        if let bar = childScrollbar(innerRect: innerRect) {
            clipChildren.append(bar)
        }

        var combinedRect: Rect = Rect(left: 0, top: 0, right: 0, bottom: 0)
        for child in clipChildren {
            combinedRect = combinedRect.union(child.rect)
        }
        let blendScope: EffectScope = session.makeScope(
            .blend(opacity: 1.0, mode: .normal),
            node: NodeKey(node),
            animatedTransform: false
        ).placed(rect: combinedRect)
        let clipped: DisplayEffect = DisplayEffect(scope: blendScope, children: clipChildren)

        var cmds: [DisplayOp] = [.effect(clipped)]
        if let border: DisplayOp = DisplayOp.fromBorderStyle(node, rect: rect) {
            cmds.append(border)
        }

        if let outline: DisplayOp = DisplayOp.fromStyle(node, rect: rect) {
            cmds.append(outline)
        }

        let wrapped: [DisplayOp] = paintBrowserVisualEffects(node: node, items: cmds, rect: rect, session: &session)
        items.replaceSubrange(start..<items.count, with: wrapped)
    }

    private func childScrollbar(innerRect: Rect) -> DisplayOp? {
        guard let frame, frame.loaded, let doc = frame.document else { return nil }
        let contentWidth: CGFloat = innerRect.right - innerRect.left
        let contentHeight: CGFloat = innerRect.bottom - innerRect.top
        guard let bar = scrollbarBarRect(
            ScrollbarGeometry(
                docHeight: doc.height + 2 * VSTEP,
                contentHeight: contentHeight,
                contentWidth: contentWidth,
                scroll: frame.scroll
            ),
            forcedColors: frame.tab?.forcedColors ?? false
        )
        else { return nil }
        guard case .rrect(let rect, let radii, let color) = bar else { return nil }
        return .rrect(rect: rect.translated(dx: innerRect.left, dy: innerRect.top), radii: radii, color: color)
    }
}
