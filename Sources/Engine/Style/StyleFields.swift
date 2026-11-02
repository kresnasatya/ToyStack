import Foundation

nonisolated final class StyleFields: FieldOwner {
    private var storage: StyleStorage = StyleStorage()
    private(set) var revision: UInt64 = 0
    private var invalidation: StyleInvalidationState = StyleInvalidationState()

    var computed: ComputedStyle { return storage.computed }
    var unknown: [String: String] { return storage.unknown }

    @MainActor
    func unknownValue(_ key: String) -> String? {
        return storage.unknown[key]
    }

    @MainActor
    func markAll() {
        invalidation.needsRestyle = true
        invalidation.dirtyKeys = Set(StyleProperty.allCases)
    }

    @MainActor
    var hasDirtyDescendant: Bool {
        return invalidation.descendantsDirty
    }

    @MainActor
    func markDirtyDescendants() {
        invalidation.descendantsDirty = true
    }

    @MainActor
    func clearDirtyDescendants() {
        invalidation.descendantsDirty = false
    }

    @MainActor
    func apply(_ newValues: [String: String], parent: ComputedStyle? = nil) {
        let old: ComputedStyle = storage.computed
        let oldUnknown: [String: String] = storage.unknown
        let parsed: (style: ComputedStyle, unknown: [String: String]) =
            ComputedStyleParser.parse(newValues, parent: parent)
        let changed: Set<StyleProperty> = parsed.style.changed(from: old)

        storage.computed = parsed.style
        storage.unknown = parsed.unknown

        invalidation.dirtyKeys.removeAll()
        invalidation.needsRestyle = false
        if !changed.isEmpty || parsed.unknown != oldUnknown {
            revision += 1
        }
        for property in changed {
            notifyDependents(property)
        }
        profiler.count("style.fields.set", by: StyleProperty.allCases.count)
        profiler.count("style.fields.changed", by: changed.count)
    }

    @MainActor
    func set(_ value: AnimatedValue, for property: StyleProperty) {
        guard storage.computed.set(value, for: property) else { return }
        invalidation.dirtyKeys.remove(property)
        revision += 1
        notifyDependents(property)
    }

    @MainActor
    func mutate(_ body: (inout ComputedStyle) -> Void) {
        let old: ComputedStyle = storage.computed
        body(&storage.computed)
        let changed: Set<StyleProperty> = storage.computed.changed(from: old)
        guard !changed.isEmpty else { return }
        invalidation.dirtyKeys.subtract(changed)
        revision += 1
        for property in changed {
            notifyDependents(property)
        }
    }

    @MainActor
    var isDirty: Bool {
        if invalidation.needsRestyle { return true }
        return !invalidation.dirtyKeys.isEmpty
    }

    @MainActor
    func field(_ key: StyleProperty) -> StyleFieldRef {
        return StyleFieldRef(owner: self, key: key)
    }

    @MainActor
    private func notifyDependents(_ key: StyleProperty) {
        guard var fields = invalidation.dependents[key] else { return }
        var dead: [FieldDependencyKey] = []
        for (id, field) in fields {
            if field.owner == nil {
                dead.append(id)
            } else {
                field.mark()
            }
        }
        for id in dead {
            fields.removeValue(forKey: id)
        }
        if fields.isEmpty {
            invalidation.dependents.removeValue(forKey: key)
        } else {
            invalidation.dependents[key] = fields
        }
    }

    @MainActor
    func markField(_ name: FieldName) {
        guard case .style(let key) = name else { return }
        invalidation.dirtyKeys.insert(key)
        notifyDependents(key)
    }

    @MainActor
    func addDependency(_ name: FieldName, _ field: FieldRef) {
        guard case .style(let key) = name, let id = FieldDependencyKey(field) else { return }
        invalidation.dependents[key, default: [:]][id] = field
    }

    @MainActor
    func removeDependency(_ name: FieldName, _ field: FieldRef) {
        guard case .style(let key) = name, let id = FieldDependencyKey(field) else { return }
        invalidation.dependents[key]?[id] = nil
        if invalidation.dependents[key]?.isEmpty == true {
            invalidation.dependents.removeValue(forKey: key)
        }
    }

    @MainActor
    func dependentCount(for key: StyleProperty) -> Int {
        return invalidation.dependents[key]?.values.reduce(0, { total, field in
            total + (field.owner == nil ? 0 : 1)
        }) ?? 0
    }

    @MainActor
    func containsDependency(_ name: FieldName, _ field: FieldRef) -> Bool {
        guard case .style(let key) = name, let id = FieldDependencyKey(field) else { return false }
        return invalidation.dependents[key]?[id]?.owner != nil
    }

    @MainActor
    func fieldIsDirty(_ name: FieldName) -> Bool {
        guard case .style(let key) = name else { return false }
        return invalidation.dirtyKeys.contains(key)
    }

    @MainActor
    func fieldIsFrozen(_ name: FieldName) -> Bool {
        return false
    }

    @MainActor
    func dependencyNames(_ name: FieldName) -> [String] {
        guard case .style(let key) = name else { return [] }
        return (invalidation.dependents[key] ?? [:])
            .compactMap({ $0.value.owner == nil ? nil : $0.value.fieldName })
            .sorted()
    }
}

// MARK: - StyleStorage

private struct StyleStorage {
    var computed: ComputedStyle = .initial
    var unknown: [String: String] = [:]
}

// MARK: - StyleInvalidationState

private struct StyleInvalidationState {
    var dirtyKeys: Set<StyleProperty> = []
    var dependents: [StyleProperty: [FieldDependencyKey: FieldRef]] = [:]
    var needsRestyle: Bool = true
    var descendantsDirty: Bool = false
}
