import CoreGraphics

// MARK: - LayoutObject
@MainActor
protocol LayoutObject: AnyObject {
    var node: any DOMNode { get }
    var parent: (any LayoutObject)? { get }
    var children: [any LayoutObject] { get set }
    var x: CGFloat { get set }
    var y: CGFloat { get set }
    var width: CGFloat { get set }
    var height: CGFloat { get set }
    var zoom: CGFloat { get set }

    func layout()
    func layout(reusesChildren: Bool)
    func paint(into items: inout [any DisplayItem])
    func shouldPaint() -> Bool
    func paintEffects(into items: inout [any DisplayItem], from start: Int)

}

extension LayoutObject {
    func layout(reusesChildren: Bool) {
        layout()
    }

    func paintEffects(into items: inout [any DisplayItem], from start: Int) {
        applyPaintEffects(into: &items, from: start)
    }

    func applyPaintEffects(into items: inout [any DisplayItem], from start: Int) {
        if self is LineLayout { return }
        let style: PaintEffectStyle? = profiler.measure("paint.effect.check", {
            paintEffectStyle(node: node)
        })
        guard let style else { return }
        let produced: [any DisplayItem] = Array(items[start...])
        let wrapped: [any DisplayItem] = profiler.measure("paint.effect.wrap", {
            paintBrowserVisualEffects(style: style, node: node, items: produced, rect: selfRect())
        })
        items.replaceSubrange(start..<items.count, with: wrapped)
    }

    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }

    func hitTest(x: CGFloat, y: CGFloat) -> (any LayoutObject)? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t = CSSValueParser.transform(node.style["transform"] ?? "") {
            x -= t.x
            y -= t.y
        }

        for child in inPaintOrder(children).reversed() {
            if let hit = child.hitTest(x: x, y: y) {
                return hit
            }
        }

        if self.x <= x && x < self.x + width && self.y <= y && y < self.y + height {
            return self
        }

        return nil
    }

    func linkElement(at x: CGFloat, y: CGFloat) -> Element? {
        var node: (any DOMNode)? = hitTest(x: x, y: y)?.node
        while let current = node {
            if let el = current as? Element, el.tag == "a", el.attributes["href"] != nil {
                return el
            }
            node = current.parent
        }
        return nil
    }

    func absoluteBounds() -> Rect {
        var rect: Rect = selfRect()
        var node: (any DOMNode)? = self.node
        while let current = node {
            if let t = CSSValueParser.transform(current.style["transform"] ?? "") {
                rect = Rect(
                    left: rect.left + t.x,
                    top: rect.top + t.y,
                    right: rect.right + t.x,
                    bottom: rect.bottom + t.y
                )
            }
            node = current.parent
        }
        return rect
    }

    func resolvedZoom() -> CGFloat {
        guard let zoomStr = node.style["zoom"] else { return parent?.zoom ?? 1.0 }
        let trimmed: String = zoomStr.trimmingCharacters(in: .whitespaces)
        let factor: CGFloat
        if trimmed.hasSuffix("%"), let pct = Double(trimmed.dropLast()) {
            factor = CGFloat(pct / 100.0)
        } else if let val = Double(trimmed) {
            factor = CGFloat(val)
        } else {
            return parent?.zoom ?? 1.0
        }
        return (parent?.zoom ?? 1.0) * factor
    }

    func scaled(_ cssPx: CGFloat) -> CGFloat {
        return cssPx * zoom
    }
}

@MainActor
func translateSubtree(_ object: any LayoutObject, dx: CGFloat, dy: CGFloat) {
    guard dx != 0 || dy != 0 else { return }
    object.x += dx
    object.y += dy
    for child in object.children { translateSubtree(child, dx: dx, dy: dy) }
}
