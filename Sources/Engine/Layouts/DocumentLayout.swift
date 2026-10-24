import CoreGraphics

// MARK: DocumentLayout
@MainActor
class DocumentLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)? = nil
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1.0
    var pageZoom: CGFloat = 1.0

    init(node: any DOMNode) {
        self.node = node
    }

    func layout() {
        layout(availableWidth: WIDTH)
    }

    func layout(reusesChildren: Bool) {
        layout(availableWidth: WIDTH, zoom: zoom, pageZoom: pageZoom, reusesChildren: reusesChildren)
    }

    func layout(availableWidth: CGFloat = WIDTH, zoom: CGFloat = 1.0, pageZoom: CGFloat = 1.0, reusesChildren: Bool = false) {
        self.zoom = zoom
        self.pageZoom = pageZoom
        let child: BlockLayout
        if reusesChildren, let existing = children.first as? BlockLayout, existing.node === node {
            child = existing
        } else {
            child = BlockLayout(node: node, parent: self, previous: nil)
        }
        children = [child]

        width = availableWidth - 2 * scaled(HSTEP)
        x = scaled(HSTEP)
        y = scaled(VSTEP)

        child.layout(reusesChildren: reusesChildren)
        height = child.height
    }

    func paint(into items: inout [any DisplayItem]) { }
    func shouldPaint() -> Bool {
        true
    }
}
