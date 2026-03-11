import CoreGraphics

// MARK: - LineLayout
// Holds one horizontal row of inline items (words, inputs).
// Its main job is baseline-aligning children with mixed font sizes.
class LineLayout: LayoutObject {
    let node: any DOMNode
    let parent: (any LayoutObject)?
    let previous: (any LayoutObject)?
    var children: [any LayoutObject] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var minHeight: CGFloat = 0

    init(node: any DOMNode, parent: any LayoutObject, previous: (any LayoutObject)?) {
        self.node = node
        self.parent = parent
        self.previous = previous
    }

    func layout() {
        width = parent!.width
        x = parent!.x
        y = previous.map { $0.y + $0.height } ?? parent!.y

        // First pass: let each child calculate its own width, x, and height.
        for child in children { child.layout() }

        // Trim trailing space from last word - no word follows it on this line.
        if let lastText = children.last as? TextLayout {
            lastText.width = lastText.font.measure(lastText.word)
        }

        guard !children.isEmpty else {
            height = minHeight
            return
        }

        // Second pass: align all children to shared baseline.
        // Each child must expose its font for ascent/descent queries.
        let inlineChildren = children.compactMap { $0 as? InlineLayoutItem }
        guard !inlineChildren.isEmpty else {
            height = 0
            return
        }

        let maxAscent = inlineChildren.map(\.font.ascent).max() ?? 0
        let baseline = y + 1.25 * maxAscent

        for child in inlineChildren {
            // Place each item so its top aligns with (baseline - its own ascent).
            child.y = baseline - child.font.ascent
        }

        let maxDescent = inlineChildren.map(\.font.descent).max() ?? 0
        // Line height adds 25% extra space above and below (the 1.25 factor).
        height = 1.25 * (maxAscent + maxDescent)
    }

    func paint() -> [any PaintCommand] { [] }
    func shouldPaint() -> Bool { true }
}
