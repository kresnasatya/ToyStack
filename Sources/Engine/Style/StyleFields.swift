import Foundation

@MainActor
final class StyleFields {
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

    func unknownValue(_ key: String) -> String? {
        return storage.unknown[key]
    }

    func markAll() {
        invalidation.needsRestyle = true
        invalidation.dirtyKeys = Set(StyleProperty.allCases)
    }

    var hasDirtyDescendant: Bool {
        return invalidation.descendantsDirty
    }

    func markDirtyDescendants() {
        invalidation.descendantsDirty = true
    }

    func clearDirtyDescendants() {
        invalidation.descendantsDirty = false
    }

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
        notifyLayout(changed)
        profiler.count("style.fields.set", by: StyleProperty.allCases.count)
        profiler.count("style.fields.changed", by: changed.count)
    }

    func set(_ value: AnimatedValue, for property: StyleProperty) {
        guard storage.computed.set(value, for: property) else { return }
        invalidation.dirtyKeys.remove(property)
        revision += 1
        notifyLayout([property])
    }

    func mutate(_ body: (inout ComputedStyle) -> Void) {
        let old: ComputedStyle = storage.computed
        body(&storage.computed)
        let changed: Set<StyleProperty> = storage.computed.changed(from: old)
        guard !changed.isEmpty else { return }
        invalidation.dirtyKeys.subtract(changed)
        revision += 1
        notifyLayout(changed)
    }

    var isDirty: Bool {
        if invalidation.needsRestyle { return true }
        return !invalidation.dirtyKeys.isEmpty
    }

    private func notifyLayout(_ changed: Set<StyleProperty>) {
        guard let owner, let tree = layoutTree else { return }
        for property in changed where property.affectsLayout {
            tree.dependencies.mark(.style(owner, property), in: tree)
        }
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
