import Foundation

nonisolated final class StyleFields: FieldOwner {
    private(set) var values: [String: String] = [:]
    private var dirtyKeys: Set<String> = []
    private var dependents: [String: [FieldRef]] = [:]
    private var needsRestyle: Bool = true
    private var descendantsDirty: Bool = false

    @MainActor
    subscript(_ key: String) -> String? {
        get {
            return values[key]
        }
        set {
            let before: String? = values[key]
            values[key] = newValue
            dirtyKeys.remove(key)
            if before != newValue {
                notifyDependents(key)
            }
        }
    }

    @MainActor
    func read(_ key: String, notify: any InvalidatableField) -> String? {
        return field(key).read(notify: notify)
    }

    @MainActor
    func markAll() {
        needsRestyle = true
        for key in values.keys {
            dirtyKeys.insert(key)
        }
    }

    @MainActor
    var hasDirtyDescendant: Bool {
        return descendantsDirty
    }

    @MainActor
    func markDirtyDescendants() {
        descendantsDirty = true
    }

    @MainActor
    func clearDirtyDescendants() {
        descendantsDirty = false
    }

    @MainActor
    func apply(_ newValues: [String: String]) {
        var written: Int = 0
        var changed: Int = 0

        for key in Array(values.keys) where newValues[key] == nil {
            values.removeValue(forKey: key)
            dirtyKeys.remove(key)
            written += 1
            changed += 1
            notifyDependents(key)
        }

        for (key, value) in newValues {
            let before: String? = values[key]
            values[key] = value
            dirtyKeys.remove(key)
            written += 1
            if before != value {
                changed += 1
                notifyDependents(key)
            }
        }

        needsRestyle = false
        profiler.count("style.fields.set", by: written)
        profiler.count("style.fields.changed", by: changed)
    }

    @MainActor
    func snapshot() -> [String: String] {
        return values
    }

    @MainActor
    var isEmpty: Bool {
        return values.isEmpty
    }

    @MainActor
    var isDirty: Bool {
        if needsRestyle { return true }
        return !dirtyKeys.isEmpty
    }

    @MainActor
    func field(_ key: String) -> StyleFieldRef {
        return StyleFieldRef(owner: self, key: key)
    }

    @MainActor
    private func notifyDependents(_ key: String) {
        guard var fields = dependents[key] else { return }
        fields.removeAll(where: { $0.owner == nil })
        dependents[key] = fields
        for field in fields {
            field.mark()
        }
    }

    @MainActor
    func markField(_ name: FieldName) {
        guard case .style(let key) = name else { return }
        dirtyKeys.insert(key)
        notifyDependents(key)
    }

    @MainActor
    func addDependency(_ name: FieldName, _ field: FieldRef) {
        guard case .style(let key) = name else { return }
        var fields: [FieldRef] = dependents[key] ?? []
        fields.removeAll(where: { $0.owner == nil })
        if !fields.contains(where: { $0.sameTarget(as: field) }) {
            fields.append(field)
        }
        dependents[key] = fields
    }

    @MainActor
    func removeDependency(_ name: FieldName, _ field: FieldRef) {
        guard case .style(let key) = name, var fields = dependents[key] else { return }
        fields.removeAll(where: { $0.owner == nil || $0.sameTarget(as: field) })
        if fields.isEmpty {
            dependents.removeValue(forKey: key)
        } else {
            dependents[key] = fields
        }
    }

    func dependentCount(for key: String) -> Int {
        return dependents[key]?.count ?? 0
    }

    @MainActor
    func containsDependency(_ name: FieldName, _ field: FieldRef) -> Bool {
        guard case .style(let key) = name else { return false }
        return dependents[key]?.contains(where: { $0.sameTarget(as: field) }) ?? false
    }

    @MainActor
    func fieldIsDirty(_ name: FieldName) -> Bool {
        guard case .style(let key) = name else { return false }
        return dirtyKeys.contains(key)
    }

    @MainActor
    func fieldIsFrozen(_ name: FieldName) -> Bool {
        return false
    }

    @MainActor
    func dependencyNames(_ name: FieldName) -> [String] {
        guard case .style(let key) = name else { return [] }
        return (dependents[key] ?? [])
            .compactMap({ $0.owner == nil ? nil : $0.fieldName })
            .sorted()
    }
}
