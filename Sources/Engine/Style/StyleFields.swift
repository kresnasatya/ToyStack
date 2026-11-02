import Foundation

nonisolated final class StyleFields {
    private(set) var owner: NodeID?
    private var storage: StyleStorage = StyleStorage()
    private(set) var revision: UInt64 = 0
    private var invalidation: StyleInvalidationState = StyleInvalidationState()
    weak var layoutTree: LayoutTree?

    var computed: ComputedStyle { return storage.computed }
    var unknown: [String: String] { return storage.unknown }

    /// Stamps the node that owns these fields. Called once by `DOMTree.register`.
    func attachOwner(_ id: NodeID) {
        owner = id
    }

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
        return StyleFieldRef(owner: self, property: key)
    }

    @MainActor
    private func styleKey(_ key: StyleProperty) -> FieldKey? {
        guard let owner else { return nil }
        return .style(owner, key)
    }

    @MainActor
    private func notifyDependents(_ key: StyleProperty) {
        guard let fieldKey = styleKey(key), let tree = layoutTree else { return }
        for ref in tree.dependencies.mark(fieldKey) {
            ref.mark()
        }
    }

    @MainActor
    func markStyle(_ key: StyleProperty) {
        invalidation.dirtyKeys.insert(key)
        notifyDependents(key)
    }

    @MainActor
    func addDependency(_ key: StyleProperty, _ dependent: FieldRef) {
        guard let fieldKey = styleKey(key), let tree = layoutTree else { return }
        tree.dependencies.add(dependent, for: fieldKey)
    }

    @MainActor
    func removeDependency(_ key: StyleProperty, _ dependent: FieldRef) {
        guard let fieldKey = styleKey(key), let tree = layoutTree else { return }
        tree.dependencies.remove(dependent, for: fieldKey)
    }

    @MainActor
    func dependentCount(for key: StyleProperty) -> Int {
        guard let fieldKey = styleKey(key), let tree = layoutTree else { return 0 }
        return tree.dependencies.count(of: fieldKey)
    }

    @MainActor
    func containsDependency(_ key: StyleProperty, _ dependent: FieldRef) -> Bool {
        guard let fieldKey = styleKey(key), let tree = layoutTree else { return false }
        return tree.dependencies.contains(fieldKey, dependent)
    }

    @MainActor
    func fieldIsDirty(_ key: StyleProperty) -> Bool {
        return invalidation.dirtyKeys.contains(key)
    }

    @MainActor
    func dependencyNames(_ key: StyleProperty) -> [String] {
        guard let fieldKey = styleKey(key), let tree = layoutTree else { return [] }
        return tree.dependencies.names(of: fieldKey)
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
    var needsRestyle: Bool = true
    var descendantsDirty: Bool = false
}
