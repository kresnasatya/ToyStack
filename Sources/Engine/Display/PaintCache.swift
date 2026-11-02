import CoreGraphics

struct PaintCache {
    private var items: [DisplayOp] = []
    private var key: PaintKey? = nil
    private var valid: Bool = false

    func canReuse(key: PaintKey) -> Bool {
        return valid && self.key == key
    }

    mutating func store(
        items: [DisplayOp],
        key: PaintKey,
        origin: Point
    ) {
        var relative: [DisplayOp] = []
        relative.reserveCapacity(items.count)
        for item in items {
            switch item {
            case .beginEffect, .endEffect, .compositedLayer:
                valid = false
                self.items.removeAll(keepingCapacity: true)
                return
            default:
                break
            }
            relative.append(item.shifted(dx: -origin.x, dy: -origin.y))
        }
        self.items = relative
        self.key = key
        self.valid = true
    }

    func append(to displayList: inout [DisplayOp], origin: Point) {
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
