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

    /// True when a queued change can move geometry, not just pixels.
    ///
    /// Paint-only properties (color, opacity, transform, z-index, …) still land
    /// in `layoutChanges` so a later layout sees them, but they must not be the
    /// reason a layout runs: a hover that only recolors text would otherwise
    /// pay a document pass.
    var hasLayoutChanges: Bool {
        return layoutChanges.contains(where: { $0.affectsLayout })
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
            StyleRevision.bump()
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
    func reapplyInherited(parent: ComputedStyle?) -> Bool? {
        guard canReinheritText else { return nil }
        let oldText: TextStyle = storage.computed.text
        let newText: TextStyle
        if inheritedText.isEmpty {
            newText = ComputedStyle.inheritingText(from: parent)
        } else {
            newText = ComputedStyleParser.parseText(inheritedText, parent: parent)
        }
        guard oldText != newText else { return false }
        var changedCount: Int = 0
        for property in StyleProperty.inherited
        where !oldText.matches(newText, for: property) {
            changedCount += 1
            layoutChanges.insert(property)
            invalidation.dirtyKeys.remove(property)
        }
        guard changedCount > 0 else { return false }

        storage.computed.text = newText
        invalidation.needsRestyle = false
        revision += 1
        StyleRevision.bump()
        return true
    }

    private func recordInheritedChanges(_ changed: Set<StyleProperty>) {
        for property in changed where StyleProperty.inherited.contains(property) {
            profiler.count(named: "style.changed.\(property.cssName)")
        }
    }

    func set(_ value: AnimatedValue, for property: StyleProperty) {
        guard storage.computed.set(value, for: property) else { return }
        invalidation.dirtyKeys.remove(property)
        canReinheritText = false
        revision += 1
        StyleRevision.bump()
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
        StyleRevision.bump()
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
