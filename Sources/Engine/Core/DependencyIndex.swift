import Foundation

/// Reverse edges from an input field to the layout fields that read it.
///
/// The graph is rebuilt from `LayoutInputTable`, which is the only place that
/// declares an edge. A write walks the index once; reads never touch it.
struct DependencyIndex {
    private var dependents: [FieldKey: Set<FieldKey>] = [:]
    private var inputsByDependent: [FieldKey: Set<FieldKey>] = [:]

    /// Replaces the whole reverse index with the static input table.
    ///
    /// Every used field of every live layout node declares its inputs once in
    /// `LayoutInputTable`; this method clears stale edges and rebuilds them.
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

    /// Layout fields that read `key`.
    ///
    /// The index is kept fresh by `reindex` at the structural and style
    /// mutation sites, so a read does not rebuild or copy it.
    func fields(for key: FieldKey) -> Set<FieldKey> {
        return dependents[key] ?? []
    }

    /// Adds one edge without rebuilding the whole graph. Used when a node is
    /// created during a layout pass, so its first field writes still reach
    /// the fields that read them.
    mutating func add(_ dependent: FieldKey, for key: FieldKey) {
        dependents[key, default: []].insert(dependent)
        inputsByDependent[dependent, default: []].insert(key)
    }

    mutating func removeDependent(_ dependent: FieldKey) {
        guard let inputs: Set<FieldKey> = inputsByDependent.removeValue(forKey: dependent) else {
            return
        }
        for key in inputs {
            dependents[key]?.remove(dependent)
            if dependents[key]?.isEmpty == true {
                dependents.removeValue(forKey: key)
            }
        }
    }

    mutating func replaceDependent(_ dependent: FieldKey, with inputs: [FieldKey]) {
        removeDependent(dependent)
        for input in inputs {
            add(dependent, for: input)
        }
    }

    mutating func reindex(_ id: LayoutID, inputs: [LayoutField: [FieldKey]]) {
        reindex(id, fields: LayoutField.allCases, inputs: inputs)
    }

    mutating func reindex(
        _ id: LayoutID,
        fields: [LayoutField],
        inputs: [LayoutField: [FieldKey]]
    ) {
        for field in fields {
            removeDependent(.layout(id, field))
        }
        for field in fields {
            guard let fieldInputs = inputs[field] else { continue }
            let dependent: FieldKey = .layout(id, field)
            for input in fieldInputs {
                add(dependent, for: input)
            }
        }
    }

    mutating func removeLayoutEdges(for id: LayoutID) {
        for field in LayoutField.allCases {
            let key: FieldKey = .layout(id, field)
            removeDependent(key)
            dependents.removeValue(forKey: key)
        }
    }

    func count(of key: FieldKey) -> Int {
        return dependents[key]?.count ?? 0
    }

    /// Input keys that the given field depends on.
    ///
    /// The index is stored input-first, so this is the inverse lookup. Internal
    /// so tests can compare the reverse index against `LayoutInputTable`.
    func fieldKeys(for dependent: FieldKey) -> Set<FieldKey> {
        var keys: Set<FieldKey> = []
        for (input, list) in dependents where list.contains(dependent) {
            keys.insert(input)
        }
        return keys
    }
}
