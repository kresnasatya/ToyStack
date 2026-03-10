import CoreGraphics

// MARK: DocumentLayout
// The root of the layout tree. Wraps the whole DOM tree in one BlockLayout child.
// Sets document-level x/y/width and delegates height computation to its child.
class DocumentLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)? = nil  // no parent - this is the root
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0

    init(node: any DOMNode) {
        self.node = node
    }

    func layout() {
        let child = BlockLayout(node: node, parent: self, previous: nil)
        children.append(child)

        // Content area starts one step from each edge to add a small margin.
        width = WIDTH - 2 * HSTEP
        x = HSTEP
        y = VSTEP

        child.layout()
        // Document height equals the single child's height.
        height = child.height
    }

    // DocumentLayout draws nothing itself - only its BlockLayout child does.
    func paint() -> [any PaintCommand] { [] }
    func shouldPaint() -> Bool {
        true
    }
}
