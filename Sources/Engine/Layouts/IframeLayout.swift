import CoreGraphics

// MARK: - IframeLayout
@MainActor
final class IframeLayout: EmbedLayout {
    static let defaultWidthPx: CGFloat = 300
    static let defaultHeightPx: CGFloat = 150

    private var frame: Frame? { (node as? Element)?.frame }

    static func displayWidth(for el: Element) -> CGFloat {
        let attr: CGFloat = el.attributes["width"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? defaultWidthPx
        return attr + 2
    }

    static func displayHeight(for el: Element) -> CGFloat {
        let attr: CGFloat = el.attributes["height"].flatMap({ Double($0) }).map({ CGFloat($0) }) ?? defaultHeightPx
        return attr + 2
    }

    override func layout() {
        super.layout()
        guard let el = node as? Element else { return }

        self.width = scaled(IframeLayout.displayWidth(for: el))
        self.height = scaled(IframeLayout.displayHeight(for: el))

        guard let frame, frame.loaded else { return }
        let innerWidth: CGFloat = self.width - scaled(2)
        let innerHeight: CGFloat = self.height - scaled(2)
        if frame.frameWidth != innerWidth || frame.frameHeight != innerHeight {
            frame.frameWidth = innerWidth
            frame.frameHeight = innerHeight
            frame.setNeedsLayout()
        }
    }

    override func paint() -> [any DisplayItem] {
        var cmds: [any DisplayCommand] = []
        let bgColor: String = node.style["background-color"] ?? "transparent"
        guard bgColor != "transparent" else { return cmds }
        let radiusStr: String = (node.style["border-radius"] ?? "0px").replacingOccurrences(of: "px", with: "")
        let radius: CGFloat = CGFloat(Double(radiusStr) ?? 0)
        cmds.append(DrawRRect(rect: selfRect(), parentEffect: nil, radius: radius, color: bgColor))
        return cmds
    }

    override func paintEffects(_ items: [any DisplayItem]) -> [any DisplayItem] {
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
        let clip: Clip = Clip(
            rect: innerRect,
            clipRect: clipRect,
            node: nil,
            children: items
        )

        let transform: Transform = Transform(
            translation: CGPoint(x: x + diff, y: y + diff - scroll),
            rect: rect,
            node: node,
            children: [clip]
        )

        var clipChildren: [any DisplayItem] = [transform]
        if let bar = childScrollbar(innerRect: innerRect) {
            clipChildren.append(bar)
        }

        let clipped: Blend = Blend(
            opacity: 1.0, blendMode: .normal, node: node, children: clipChildren
        )

        var cmds: [any DisplayItem] = [clipped]
        if let border: DrawOutline = DrawOutline.fromBorderStyle(node, rect: rect) {
            cmds.append(border)
        }
        if let outline: DrawOutline = DrawOutline.fromStyle(node, rect: rect) {
            cmds.append(outline)
        }
        return paintBrowserVisualEffects(node: node, items: cmds, rect: rect)
    }

    private func childScrollbar(innerRect: Rect) -> ScrollbarBar? {
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
        return ScrollbarBar(
            rect: Rect(
                left: innerRect.left + bar.rect.left,
                top: innerRect.top + bar.rect.top,
                right: innerRect.left + bar.rect.right,
                bottom: innerRect.top + bar.rect.bottom
            ),
            color: bar.color
        )
    }
}
