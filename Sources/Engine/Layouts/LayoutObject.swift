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
    func paint() -> [Any]
    func shouldPaint() -> Bool

}

extension LayoutObject {
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
}

protocol InlineLayoutItem: LayoutObject {
    var font: BrowserFont { get }
}
