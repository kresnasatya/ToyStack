import CoreGraphics

// MARK: - LayoutObject
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
    func paint() -> [any DisplayItem]
    func shouldPaint() -> Bool

}

extension LayoutObject {
    func selfRect() -> Rect {
        Rect(left: x, top: y, right: x + width, bottom: y + height)
    }

    func hitTest(x: CGFloat, y: CGFloat) -> (any LayoutObject)? {
        var x: CGFloat = x
        var y: CGFloat = y

        if let t = parseTransform(node.style["transform"] ?? "") {
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
