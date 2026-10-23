import CoreGraphics

struct LinePaintCache {
    private var items: [any DisplayCommand] = []
    private var key: LinePaintKey? = nil
    private var valid: Bool = false

    func canReuse(epoch: UInt, generation: UInt) -> Bool {
        guard valid, let key else { return false }
        return key.epoch == epoch && key.generation == generation
    }

    mutating func store(items: [any DisplayItem], key: LinePaintKey) {
        var commands: [any DisplayCommand] = []
        commands.reserveCapacity(items.count)
        for item in items {
            guard let command = item as? any DisplayCommand, command is DrawText || command is DrawOutline
            else {
                valid = false
                self.items.removeAll(keepingCapacity: true)
                return
            }
            commands.append(command)
        }
        self.items = commands
        self.key = key
        self.valid = true
    }

    func append(
        to displayList: inout [any DisplayItem],
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
