import CoreGraphics

struct LinePaintCache: Sendable {
    private var items: [DisplayOp] = []
    private var key: LinePaintKey? = nil
    private var valid: Bool = false

    func canReuse(epoch: UInt, version: LinePaintVersion) -> Bool {
        guard valid, let key else { return false }
        return key.epoch == epoch && key.version == version
    }

    mutating func store(items: [DisplayOp], key: LinePaintKey) {
        var commands: [DisplayOp] = []
        commands.reserveCapacity(items.count)
        for item in items {
            switch item {
            case .text, .outline:
                commands.append(item)
            default:
                valid = false
                self.items.removeAll(keepingCapacity: true)
                return
            }
        }
        self.items = commands
        self.key = key
        self.valid = true
    }

    func append(
        to displayList: inout [DisplayOp],
        currentX: CGFloat,
        currentY: CGFloat
    ) {
        guard valid, let key else { return }
        let dx: CGFloat = currentX - key.x
        let dy: CGFloat = currentY - key.y
        if dx == 0 && dy == 0 {
            for item in items { displayList.append(item) }
            return
        }
        for item in items {
            displayList.append(item.shifted(dx: dx, dy: dy))
        }
    }
}
