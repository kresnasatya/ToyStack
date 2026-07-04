import CoreGraphics

// MARK: - LayoutObject Protocol
// Every node in the layout tree implements these. The protocol lets
// paintTree(), treeToList(), and Tab.draw() work generically accross all types.
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

// MARK: - Hit Testing
// Walk the layout tree converting the click point into each object's
// coordinate space, instead of converting every object's bounds to
// absolute coordinates. Only transforms need mapping: our layout x/y
// are already document-absolute
extension LayoutObject {
    func hitTest(x: CGFloat, y: CGFloat) -> (any LayoutObject)? {
        var x = x
        var y = y

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
}

// MARK: - InlineLayoutItem
// TextLayout and InputLayout both live inside a LineLayout.
// This protocol lets LineLayout read font metrics and set y positions.
protocol InlineLayoutItem: LayoutObject {
    var font: BrowserFont { get }
}
