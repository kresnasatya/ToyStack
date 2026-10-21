import CoreGraphics

struct PaintCache {
    private var items: [any DisplayItem] = []
    private var key: PaintKey? = nil
    private var valid: Bool = false

    func canReuse(key: PaintKey) -> Bool {
        return valid && self.key == key
    }

    mutating func store(
        items: [any DisplayItem],
        key: PaintKey
    ) {
        guard !items.contains(where: { $0 is BrowserVisualEffect }) else {
            valid = false
            return
        }
        self.items = items
        self.key = key
        self.valid = true
    }

    func append(to displayList: inout [any DisplayItem]) {
        guard valid else { return }
        displayList.append(contentsOf: items)
    }

    mutating func invalidate() {
        valid = false
    }
}
