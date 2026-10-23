import CoreGraphics

struct PaintCache {
    private var items: [any DisplayCommand] = []
    private var key: PaintKey? = nil
    private var valid: Bool = false

    func canReuse(key: PaintKey) -> Bool {
        return valid && self.key == key
    }

    mutating func store(
        items: [any DisplayItem],
        key: PaintKey,
        origin: Point
    ) {
        var relative: [any DisplayCommand] = []
        relative.reserveCapacity(items.count)
        for item in items {
            guard let command = item as? any DisplayCommand, !(command is DrawCompositedLayer)
            else {
                valid = false
                self.items.removeAll(keepingCapacity: true)
                return
            }
            relative.append(command.shifted(dx: -origin.x, dy: -origin.y))
        }
        self.items = relative
        self.key = key
        self.valid = true
    }

    func append(to displayList: inout [any DisplayItem], origin: Point) {
        guard valid else { return }
        for item in items {
            displayList.append(item.shifted(dx: origin.x, dy: origin.y))
        }
    }

    mutating func invalidate() {
        valid = false
        self.items.removeAll(keepingCapacity: true)
    }
}
