import CoreGraphics

// MARK: - InlinePlacement

@MainActor
struct InlinePlacement {
    private(set) var lines: [any LayoutObject] = []
    private(set) var currentLine: LineLayout? = nil
    private(set) var children: [any LayoutObject] = []
    var cursorX: CGFloat = 0

    mutating func start(parent: any LayoutObject) {
        let previous: (any LayoutObject)? = lines.last
        currentLine = LineLayout(node: parent.node, parent: parent, previous: previous)
        children = []
        cursorX = 0
    }

    mutating func endLine(parent: any LayoutObject) {
        guard let line = currentLine else { return }
        line.children = children
        lines.append(line)
        start(parent: parent)
    }

    mutating func finish() {
        guard let line = currentLine else { return }
        line.children = children
        lines.append(line)
        currentLine = nil
        children = []
    }

    mutating func append(_ child: any LayoutObject) {
        children.append(child)
    }
}
