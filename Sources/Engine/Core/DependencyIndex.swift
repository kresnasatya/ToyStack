import Foundation

/// Reverse edges from an input field to the fields that read it.
///
/// This is the single dependency graph for one `LayoutTree`. Handles add an
/// edge when a read is not declared frozen; a write walks the index once.
@MainActor
struct DependencyIndex {
    private var dependents: [FieldKey: [FieldRef]] = [:]

    mutating func add(_ dependent: FieldRef, for key: FieldKey) {
        guard dependent.isAlive else { return }
        var list: [FieldRef] = (dependents[key] ?? []).filter({ $0.isAlive })
        guard !list.contains(where: { $0.fieldKey == dependent.fieldKey }) else {
            dependents[key] = list
            return
        }
        list.append(dependent)
        dependents[key] = list
    }

    mutating func remove(_ dependent: FieldRef, for key: FieldKey) {
        guard var list: [FieldRef] = dependents[key] else { return }
        list.removeAll(where: { $0.fieldKey == dependent.fieldKey })
        dependents[key] = list.isEmpty ? nil : list
    }

    mutating func mark(_ key: FieldKey) -> [FieldRef] {
        let live: [FieldRef] = (dependents[key] ?? []).filter({ $0.isAlive })
        if live.isEmpty {
            dependents[key] = nil
        } else {
            dependents[key] = live
        }
        return live
    }

    func contains(_ key: FieldKey, _ dependent: FieldRef) -> Bool {
        return dependents[key]?.contains(where: {
            $0.fieldKey == dependent.fieldKey && $0.isAlive
        }) ?? false
    }

    func names(of key: FieldKey) -> [String] {
        return (dependents[key] ?? []).filter({ $0.isAlive }).map({ $0.fieldName }).sorted()
    }

    func count(of key: FieldKey) -> Int {
        return dependents[key]?.filter({ $0.isAlive }).count ?? 0
    }
}
