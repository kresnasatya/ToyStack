import CoreGraphics

// MARK: - LayoutFieldStore

@MainActor
struct LayoutFieldStore {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var width: CGFloat = 0
    var height: CGFloat = 0
    var zoom: CGFloat = 1
    var children: [any LayoutObject] = []
    var previous: (any LayoutObject)? = nil
    var font: BrowserFont = inlineDefaultFont
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var inlineContent: UInt64 = 0

    private var usedBits: UInt16 = 0
    private var dirtyBits: UInt16 = LayoutField.allMask
    private var frozenBits: UInt16 = 0
    private var dependents: [LayoutField: [FieldDependencyKey: FieldRef]] = [:]

    func isUsed(_ field: LayoutField) -> Bool {
        return usedBits & field.mask != 0
    }

    func isDirty(_ field: LayoutField) -> Bool {
        return dirtyBits & field.mask != 0
    }

    func isFrozen(_ field: LayoutField) -> Bool {
        return frozenBits & field.mask != 0
    }

    mutating func markUsed(_ field: LayoutField) {
        usedBits |= field.mask
    }

    mutating func markDirty(_ field: LayoutField) {
        dirtyBits |= field.mask
    }

    mutating func markClean(_ field: LayoutField) {
        dirtyBits &= ~field.mask
    }

    mutating func markFrozen(_ field: LayoutField) {
        frozenBits |= field.mask
    }

    mutating func addDependent(_ field: LayoutField, _ dependent: FieldRef) {
        guard let id = FieldDependencyKey(dependent) else { return }
        dependents[field, default: [:]][id] = dependent
    }

    mutating func removeDependent(_ field: LayoutField, _ dependent: FieldRef) {
        guard let id = FieldDependencyKey(dependent), var current = dependents[field] else {
            return
        }
        current.removeValue(forKey: id)
        if current.isEmpty {
            dependents.removeValue(forKey: field)
        } else {
            dependents[field] = current
        }
    }

    func dependentCount(_ field: LayoutField) -> Int {
        return dependents[field]?.values.reduce(0, { total, ref in
            total + (ref.owner == nil ? 0 : 1)
        }) ?? 0
    }

    func containsDependent(_ field: LayoutField, _ dependent: FieldRef) -> Bool {
        guard let id = FieldDependencyKey(dependent) else { return false }
        return dependents[field]?[id]?.owner != nil
    }

    func dependencyNames(_ field: LayoutField) -> [String] {
        return (dependents[field] ?? [:])
            .compactMap({ $0.value.owner == nil ? nil : $0.value.fieldName })
            .sorted()
    }

    mutating func takeDependents(_ field: LayoutField) -> [FieldRef] {
        guard let current = dependents[field] else { return [] }
        var live: [FieldRef] = []
        live.reserveCapacity(current.count)
        for ref in current.values where ref.owner != nil {
            live.append(ref)
        }
        if live.count != current.count {
            dependents[field] = current.filter({ $0.value.owner != nil })
        }
        return live
    }
}
