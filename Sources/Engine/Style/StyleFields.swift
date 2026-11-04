import Foundation

@MainActor
final class StyleFields {
    private var storage: StyleStorage = StyleStorage()
    private(set) var revision: UInt64 = 0
    private var invalidation: StyleInvalidationState = StyleInvalidationState()
    private var layoutChanges: Set<StyleProperty> = []
    private var inheritedText: [String: String] = [:]
    private var canReinheritText: Bool = false

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
        applyValues(newValues, parent: parent, textDeclarations: nil)
    }

    func apply(
        _ newValues: [String: String],
        parent: ComputedStyle?,
        textDeclarations: [String: String]
    ) {
        applyValues(newValues, parent: parent, textDeclarations: textDeclarations)
    }

    private func applyValues(
        _ newValues: [String: String],
        parent: ComputedStyle?,
        textDeclarations: [String: String]?
    ) {
        let old: ComputedStyle = storage.computed
        let oldUnknown: [String: String] = storage.unknown
        let parsed: (style: ComputedStyle, unknown: [String: String]) =
            ComputedStyleParser.parse(newValues, parent: parent)
        let changed: Set<StyleProperty> = parsed.style.changed(from: old)

        storage.computed = parsed.style
        storage.unknown = parsed.unknown
        inheritedText = textDeclarations ?? [:]
        canReinheritText = textDeclarations != nil

        invalidation.dirtyKeys.removeAll()
        invalidation.needsRestyle = false
        if !changed.isEmpty || parsed.unknown != oldUnknown {
            revision += 1
        }
        layoutChanges.formUnion(changed)
        recordInheritedChanges(changed)
        profiler.count("style.fields.set", by: StyleProperty.allCases.count)
        profiler.count("style.fields.changed", by: changed.count)
    }

    /// Reapplies only the inherited text properties from the parent.
    ///
    /// A force-only node did not match a new rule; its own declarations are
    /// unchanged and only inherited text can move. Returns `nil` when no
    /// declaration cache is available and the full cascade must run.
    func reapplyInherited(parent: ComputedStyle?) -> Set<StyleProperty>? {
        guard canReinheritText else { return nil }
        let old: ComputedStyle = storage.computed
        let newText: TextStyle
        if inheritedText.isEmpty {
            newText = ComputedStyle.inheriting(from: parent).text
            profiler.count("style.reapplyInherited.empty")
        } else {
            let parsed: (style: ComputedStyle, unknown: [String: String]) =
                ComputedStyleParser.parse(inheritedText, parent: parent)
            newText = parsed.style.text
        }
        var style: ComputedStyle = old
        style.text = newText
        var changed: Set<StyleProperty> = []
        for property in StyleProperty.inherited
        where !old.matches(style, for: property) {
            changed.insert(property)
        }
        guard !changed.isEmpty else { return [] }

        storage.computed = style
        invalidation.dirtyKeys.subtract(changed)
        invalidation.needsRestyle = false
        revision += 1
        layoutChanges.formUnion(changed)
        recordInheritedChanges(changed)
        profiler.count("style.fields.changed", by: changed.count)
        profiler.count("style.apply.inherited", by: 1)
        return changed
    }

    private func recordInheritedChanges(_ changed: Set<StyleProperty>) {
        for property in changed where StyleProperty.inherited.contains(property) {
            profiler.count("style.changed.\(property.cssName)")
        }
    }

    func set(_ value: AnimatedValue, for property: StyleProperty) {
        guard storage.computed.set(value, for: property) else { return }
        invalidation.dirtyKeys.remove(property)
        canReinheritText = false
        revision += 1
        layoutChanges.insert(property)
    }

    func mutate(_ body: (inout ComputedStyle) -> Void) {
        let old: ComputedStyle = storage.computed
        body(&storage.computed)
        let changed: Set<StyleProperty> = storage.computed.changed(from: old)
        guard !changed.isEmpty else { return }
        canReinheritText = false
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
