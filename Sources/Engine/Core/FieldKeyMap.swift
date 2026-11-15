import Foundation

struct FieldKeyMap {
    private var layout: [Set<FieldKey>] = []
    private var style: [FieldKey: Set<FieldKey>] = [:]

    private static let fieldCount: Int = LayoutField.allCases.count

    private static func slot(_ id: LayoutID, _ field: LayoutField) -> Int {
        return id.raw * fieldCount + field.mask.trailingZeroBitCount
    }

    private mutating func grow(to slot: Int) {
        guard slot >= layout.count else { return }
        layout.append(contentsOf: repeatElement([], count: slot + 1 - layout.count))
    }

    subscript(key: FieldKey) -> Set<FieldKey>? {
        get {
            switch key {
            case .layout(let id, let field):
                let slot: Int = Self.slot(id, field)
                guard slot < layout.count, !layout[slot].isEmpty else { return nil }
                return layout[slot]
            case .style:
                return style[key]
            }
        }
        _modify {
            switch key {
            case .layout(let id, let field):
                let slot: Int = Self.slot(id, field)
                grow(to: slot)
                var value: Set<FieldKey>? = layout[slot].isEmpty ? nil : layout[slot]
                layout[slot] = []
                defer { layout[slot] = value ?? [] }
                yield &value
            case .style:
                yield &style[key]
            }
        }
    }

    subscript(
        key: FieldKey,
        default defaultValue: @autoclosure () -> Set<FieldKey>
    ) -> Set<FieldKey> {
        get { return self[key] ?? defaultValue() }
        _modify {
            switch key {
            case .layout(let id, let field):
                let slot: Int = Self.slot(id, field)
                grow(to: slot)
                var value: Set<FieldKey> = layout[slot]
                layout[slot] = []
                defer { layout[slot] = value }
                yield &value
            case .style:
                yield &style[key, default: defaultValue()]
            }
        }
    }

    @discardableResult
    mutating func removeValue(forKey key: FieldKey) -> Set<FieldKey>? {
        switch key {
        case .layout(let id, let field):
            let slot: Int = Self.slot(id, field)
            guard slot < layout.count, !layout[slot].isEmpty else { return nil }
            let value: Set<FieldKey> = layout[slot]
            layout[slot] = []
            return value
        case .style:
            return style.removeValue(forKey: key)
        }
    }

    mutating func removeAll(keepingCapacity: Bool) {
        layout.removeAll(keepingCapacity: keepingCapacity)
        style.removeAll(keepingCapacity: keepingCapacity)
    }

    var pairs: [(key: FieldKey, value: Set<FieldKey>)] {
        var result: [(key: FieldKey, value: Set<FieldKey>)] = []
        let nodeCount: Int = (layout.count + Self.fieldCount - 1) / Self.fieldCount
        for raw in 0..<nodeCount {
            for field in LayoutField.allCases {
                let slot: Int = Self.slot(LayoutID(raw: raw), field)
                guard slot < layout.count, !layout[slot].isEmpty else { continue }
                result.append((key: .layout(LayoutID(raw: raw), field), value: layout[slot]))
            }
        }
        for (key, value) in style {
            result.append((key: key, value: value))
        }
        return result
    }
}
