import Foundation

/// Reverse edges from an input field to the fields that read it.
///
/// The index is rebuilt once per layout pass from the static input table.
/// Until that table exists, callers add and remove edges directly.
struct DependencyIndex {
    private var dependents: [FieldKey: [FieldKey]] = [:]

    mutating func add(_ dependent: FieldKey, for key: FieldKey) {
        var list: [FieldKey] = dependents[key] ?? []
        guard !list.contains(dependent) else { return }
        list.append(dependent)
        dependents[key] = list
    }

    mutating func remove(_ dependent: FieldKey, for key: FieldKey) {
        guard var list: [FieldKey] = dependents[key] else { return }
        list.removeAll(where: { $0 == dependent })
        dependents[key] = list.isEmpty ? nil : list
    }

    /// Replaces every edge into `dependent` with edges from `inputs`.
    mutating func replace(_ inputs: [FieldKey], for dependent: FieldKey) {
        for key in Array(dependents.keys) {
            remove(dependent, for: key)
        }
        for input in inputs {
            add(dependent, for: input)
        }
    }

    /// Fields to mark dirty when `key` changes.
    func mark(_ key: FieldKey) -> [FieldKey] {
        return dependents[key] ?? []
    }
}
