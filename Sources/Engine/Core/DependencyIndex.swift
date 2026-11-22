import Foundation

struct DependencyIndex {
    private var storage: DependencyStorage = DependencyStorage()

    private var dependents: FieldKeyMap {
        _read { yield storage.dependents }
        _modify {
            makeUnique()
            yield &storage.dependents
        }
    }

    private var inputsByDependent: [FieldKey: Set<FieldKey>] {
        _read { yield storage.inputsByDependent }
        _modify {
            makeUnique()
            yield &storage.inputsByDependent
        }
    }

    mutating func hasNoOtherOwner() -> Bool {
        return isKnownUniquelyReferenced(&storage)
    }

    private mutating func makeUnique() {
        guard !isKnownUniquelyReferenced(&storage) else { return }
        profiler.count("layout.dependencies.copy")
        storage = storage.copy()
    }

    mutating func rebuild(from tree: LayoutTree) {
        dependents.removeAll(keepingCapacity: true)
        inputsByDependent.removeAll(keepingCapacity: true)
        for id in tree.liveIDs {
            for field in LayoutField.allCases where tree.isUsed(field, at: id) {
                let dependent: FieldKey = .layout(id, field)
                for input in LayoutInputTable.inputs(for: id, field: field, in: tree) {
                    add(dependent, for: input)
                }
            }
        }
    }

    func fields(for key: FieldKey) -> Set<FieldKey> {
        return dependents[key] ?? []
    }

    mutating func add(_ dependent: FieldKey, for key: FieldKey) {
        dependents[key, default: []].insert(dependent)
        inputsByDependent[dependent, default: []].insert(key)
    }

    mutating func removeDependent(
        _ dependent: FieldKey,
        skippingRemoved removed: Set<LayoutID>? = nil
    ) {
        guard let inputs: Set<FieldKey> = inputsByDependent.removeValue(forKey: dependent) else {
            return
        }
        for key in inputs {
            if let removed, case .layout(let owner, _) = key, removed.contains(owner) {
                continue
            }
            dependents[key]?.remove(dependent)
            if dependents[key]?.isEmpty == true {
                dependents.removeValue(forKey: key)
            }
        }
    }

    mutating func removeEdge(_ dependent: FieldKey, for input: FieldKey) {
        inputsByDependent[dependent]?.remove(input)
        dependents[input]?.remove(dependent)
        if dependents[input]?.isEmpty == true {
            dependents.removeValue(forKey: input)
        }
    }

    mutating func replaceDependent(_ dependent: FieldKey, with inputs: [FieldKey]) {
        let next: Set<FieldKey> = Set(inputs)
        guard let current: Set<FieldKey> = inputsByDependent[dependent] else {
            inputsByDependent[dependent] = next
            for input in next {
                dependents[input, default: []].insert(dependent)
            }
            return
        }
        if current == next {
            profiler.count("layout.dependencies.replaceSkipped")
            return
        }
        for input in current where !next.contains(input) {
            dependents[input]?.remove(dependent)
            if dependents[input]?.isEmpty == true {
                dependents.removeValue(forKey: input)
            }
        }
        for input in next where !current.contains(input) {
            dependents[input, default: []].insert(dependent)
        }
        inputsByDependent[dependent] = next
    }

    mutating func reindex(_ id: LayoutID, inputs: [LayoutField: [FieldKey]]) {
        reindex(id, fields: LayoutField.allCases, inputs: inputs)
    }

    mutating func replaceInput(
        _ dependent: FieldKey,
        old: FieldKey,
        new: FieldKey
    ) {
        guard old != new,
            var inputs: Set<FieldKey> = inputsByDependent[dependent],
            inputs.contains(old)
        else { return }
        inputs.remove(old)
        inputs.insert(new)
        inputsByDependent[dependent] = inputs

        dependents[old]?.remove(dependent)
        if dependents[old]?.isEmpty == true {
            dependents.removeValue(forKey: old)
        }
        dependents[new, default: []].insert(dependent)
    }

    mutating func reindex(
        _ id: LayoutID,
        fields: [LayoutField],
        inputs: [LayoutField: [FieldKey]]
    ) {
        for field in fields {
            replaceDependent(.layout(id, field), with: inputs[field] ?? [])
        }
    }

    mutating func removeInputKey(_ key: FieldKey) {
        dependents.removeValue(forKey: key)
    }

    mutating func removeLayoutEdges(for id: LayoutID) {
        for field in LayoutField.allCases {
            let key: FieldKey = .layout(id, field)
            removeDependent(key)
            dependents.removeValue(forKey: key)
        }
    }

    mutating func removeLayoutEdges(for ids: Set<LayoutID>) {
        guard !ids.isEmpty else { return }
        profiler.measure("layout.sweep.edges.dependents", {
            for id in ids {
                for field in LayoutField.allCases {
                    removeDependent(.layout(id, field), skippingRemoved: ids)
                }
            }
        })
        profiler.measure("layout.sweep.edges.keys", {
            for id in ids {
                for field in LayoutField.allCases {
                    dependents.removeValue(forKey: .layout(id, field))
                }
            }
        })
    }

    func count(of key: FieldKey) -> Int {
        return dependents[key]?.count ?? 0
    }

    func fieldKeys(for dependent: FieldKey) -> Set<FieldKey> {
        var keys: Set<FieldKey> = []
        for (input, list) in dependents.pairs where list.contains(dependent) {
            keys.insert(input)
        }
        return keys
    }
}

// MARK: - DependencyStorage

private final class DependencyStorage {
    var dependents: FieldKeyMap
    var inputsByDependent: [FieldKey: Set<FieldKey>]

    init(
        dependents: FieldKeyMap = FieldKeyMap(),
        inputsByDependent: [FieldKey: Set<FieldKey>] = [:]
    ) {
        self.dependents = dependents
        self.inputsByDependent = inputsByDependent
    }

    func copy() -> DependencyStorage {
        return DependencyStorage(dependents: dependents, inputsByDependent: inputsByDependent)
    }
}
