import Foundation

/// Reverse edges from an input field to the layout fields that read it.
///
/// The graph is rebuilt from `LayoutInputTable`, which is the only place that
/// declares an edge. A write walks the index once; reads never touch it.
struct DependencyIndex {
    private var dependents: [FieldKey: [FieldKey]] = [:]
    private var stale: Bool = false
    private var layoutDepth: Int = 0

    mutating func beginLayout() {
        layoutDepth += 1
    }

    mutating func endLayout(from tree: LayoutTree) {
        layoutDepth -= 1
        rebuild(from: tree)
    }

    /// Records a structural change for the next write outside a layout pass.
    /// Inside a layout pass the pass rebuilds once at the end, so mutating the
    /// index per child would only add quadratic work.
    mutating func noteStructureChanged() {
        if layoutDepth == 0 {
            stale = true
        }
    }

    /// Replaces the whole reverse index with the static input table.
    ///
    /// Every used field of every live layout node declares its inputs once in
    /// `LayoutInputTable`; this method clears stale edges and rebuilds them.
    mutating func rebuild(from tree: LayoutTree) {
        dependents.removeAll(keepingCapacity: true)
        stale = false
        for id in tree.liveIDs {
            for field in LayoutField.allCases where tree.isUsed(field, at: id) {
                let dependent: FieldKey = .layout(id, field)
                for input in LayoutInputTable.inputs(for: id, field: field, in: tree) {
                    var list: [FieldKey] = dependents[input] ?? []
                    guard !list.contains(dependent) else {
                        dependents[input] = list
                        continue
                    }
                    list.append(dependent)
                    dependents[input] = list
                }
            }
        }
    }

    /// Layout fields that read `key`.
    ///
    /// The index is kept fresh by the layout pass (`rebuild` at its start) and
    /// by structural changes, so a read does not rebuild or copy it.
    func fields(for key: FieldKey) -> [FieldKey] {
        return dependents[key] ?? []
    }

    /// Adds one edge without rebuilding the whole graph. Used when a node is
    /// created during a layout pass, so its first field writes still reach
    /// the fields that read them.
    mutating func add(_ dependent: FieldKey, for key: FieldKey) {
        var list: [FieldKey] = dependents[key] ?? []
        guard !list.contains(dependent) else {
            dependents[key] = list
            return
        }
        list.append(dependent)
        dependents[key] = list
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
