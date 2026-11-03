import Foundation

@MainActor
final class StyleFields {
    private var storage: StyleStorage = StyleStorage()
    private(set) var revision: UInt64 = 0
    private var invalidation: StyleInvalidationState = StyleInvalidationState()
    private var layoutChanges: Set<StyleProperty> = []

    var computed: ComputedStyle { return storage.computed }
    var unknown: [String: String] { return storage.unknown }

    /// Properties that changed since layout last asked, consumed on read.
    ///
    /// Style writes do not reach into the layout tree; the tree asks for this
    /// set when it starts a pass.
    func takeLayoutChanges() -> Set<StyleProperty> {
        guard !layoutChanges.isEmpty else { return [] }
        let changes: Set<StyleProperty> = layoutChanges
        layoutChanges.removeAll(keepingCapacity: true)
        return changes
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
        layoutChanges.formUnion(changed)
        profiler.count("style.fields.set", by: StyleProperty.allCases.count)
        profiler.count("style.fields.changed", by: changed.count)
    }

    func set(_ value: AnimatedValue, for property: StyleProperty) {
        guard storage.computed.set(value, for: property) else { return }
        invalidation.dirtyKeys.remove(property)
        revision += 1
        layoutChanges.insert(property)
    }

    func mutate(_ body: (inout ComputedStyle) -> Void) {
        let old: ComputedStyle = storage.computed
        body(&storage.computed)
        let changed: Set<StyleProperty> = storage.computed.changed(from: old)
        guard !changed.isEmpty else { return }
        invalidation.dirtyKeys.subtract(changed)
        revision += 1
        layoutChanges.formUnion(changed)
    }

    var isDirty: Bool {
        if invalidation.needsRestyle { return true }
        return !invalidation.dirtyKeys.isEmpty
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
