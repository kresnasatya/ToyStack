import CoreGraphics

// MARK: DocumentLayout
class DocumentLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)? = nil
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1.0

    init(node: any DOMNode) {
        self.node = node
    }

    func layout() {
        layout(availableWidth: WIDTH)
    }

    func layout(availableWidth: CGFloat = WIDTH, zoom: CGFloat = 1.0) {
        self.zoom = zoom
        let child = BlockLayout(node: node, parent: self, previous: nil)
        children.append(child)

        width = availableWidth - 2 * dpx(HSTEP, zoom: zoom)
        x = dpx(HSTEP, zoom: zoom)
        y = dpx(VSTEP, zoom: zoom)

        child.layout()
        height = child.height
    }

    func paint() -> [Any] { [] }
    func shouldPaint() -> Bool {
        true
    }
}
