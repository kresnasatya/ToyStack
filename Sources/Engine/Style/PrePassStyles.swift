struct PrePassStyles {
    enum Entry: Equatable {
        case full(ComputedStyle)
        case text(TextStyle)
    }

    private enum Slot {
        case full(Int)
        case text(Int)
    }

    private var slots: [Slot] = []
    private var styles: [ComputedStyle] = []
    private var texts: [TextStyle] = []

    mutating func append(_ style: ComputedStyle) {
        slots.append(.full(styles.count))
        styles.append(style)
    }

    mutating func append(text: TextStyle) {
        slots.append(.text(texts.count))
        texts.append(text)
    }

    subscript(index: Int) -> Entry {
        switch slots[index] {
        case .full(let slot):
            return .full(styles[slot])
        case .text(let slot):
            return .text(texts[slot])
        }
    }
}
