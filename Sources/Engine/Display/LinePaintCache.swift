import CoreGraphics

struct LinePaintCache {
    private var items: [any DisplayItem] = []
    private var key: LinePaintKey? = nil
    private var valid: Bool = false

    func canReuse(epoch: UInt, generation: UInt) -> Bool {
        guard valid, let key else { return false }
        return key.epoch == epoch && key.generation == generation
    }

    mutating func store(items: [any DisplayItem], key: LinePaintKey) {
        guard items.allSatisfy({ $0 is DrawText || $0 is DrawOutline }) else {
            valid = false
            return
        }
        self.items = items
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
            displayList.append(contentsOf: items)
            return
        }
        for item in items {
            displayList.append(shifted(item, dx: dx, dy: dy))
        }
    }
}

private func shifted(
    _ item: any DisplayItem,
    dx: CGFloat,
    dy: CGFloat
) -> any DisplayItem {
    if let text = item as? DrawText {
        return DrawText(
            rect: offset(text.rect, dx: dx, dy: dy),
            text: text.text,
            font: text.font,
            color: text.color
        )
    }
    if let outline = item as? DrawOutline {
        return DrawOutline(
            rect: offset(outline.rect, dx: dx, dy: dy),
            color: outline.color,
            thickness: outline.thickness
        )
    }
    preconditionFailure("Unsupported line item: \(type(of: item))")
}

private func offset(_ rect: Rect, dx: CGFloat, dy: CGFloat) -> Rect {
    return Rect(
        left: rect.left + dx,
        top: rect.top + dy,
        right: rect.right + dx,
        bottom: rect.bottom + dy
    )
}
