import CoreGraphics

// MARK: - LayoutFieldHandle

/// Temporary bridge that gives an arena node the field read/write API the old
/// class hierarchy exposed. The owner is a `LayoutRef` value; no layout class
/// pointer survives here.
@MainActor
struct LayoutFieldHandle<Access: LayoutFieldAccess>: InvalidatableField {
    let owner: LayoutRef
    let field: LayoutField

    init(owner: LayoutRef, field: LayoutField) {
        self.owner = owner
        self.field = field
    }

    var fieldKey: FieldKey { .layout(owner.id, field) }
    var key: FieldKey { fieldKey }
    var fieldName: String { field.rawValue }
    var dirty: Bool { isDirty }
    var isDirty: Bool { owner.tree.isDirty(field, at: owner.id) }
    var frozenDependencies: Bool { owner.tree.isFrozen(field, at: owner.id) }
    var invalidationNames: [String] { owner.tree.dependencies.names(of: key) }
    var ref: FieldRef {
        let tree: LayoutTree = owner.tree
        let id: LayoutID = owner.id
        let field: LayoutField = self.field
        return FieldRef(
            key: key,
            markBody: { [weak tree] in
                tree?.markField(field, at: id)
            },
            isAlive: { [weak tree] in
                tree?.contains(id) ?? false
            }
        )
    }

    func get() -> Access.Value {
        if owner.tree.isDirty(field, at: owner.id) {
            assertionFailure("Read dirty field \(owner.kind).\(field.rawValue)")
        }
        guard owner.tree.isUsed(field, at: owner.id) else {
            fatalError("Read unset field \(owner.kind).\(field.rawValue)")
        }
        return Access.read(owner.tree, owner.id, field)
    }

    func peek() -> Access.Value? {
        guard owner.tree.isUsed(field, at: owner.id) else { return nil }
        return Access.read(owner.tree, owner.id, field)
    }

    func set(_ newValue: Access.Value) {
        let wasUsed: Bool = owner.tree.isUsed(field, at: owner.id)
        let old: Access.Value = Access.read(owner.tree, owner.id, field)
        let changed: Bool = !wasUsed || !Access.equals(old, newValue)
        owner.tree.markUsed(field, at: owner.id)
        Access.write(owner.tree, owner.id, field, newValue)
        owner.tree.markClean(field, at: owner.id)
        if changed {
            profiler.count("layout.field.set")
            owner.tree.markDependents(key)
        }
    }

    func setClean(_ newValue: Access.Value) {
        owner.tree.markUsed(field, at: owner.id)
        Access.write(owner.tree, owner.id, field, newValue)
        owner.tree.markClean(field, at: owner.id)
    }

    func mark() {
        owner.tree.markField(field, at: owner.id)
    }

    func copy(from field: LayoutFieldHandle<Access>) {
        set(field.read(notify: self))
    }

    func read(notify: any InvalidatableField) -> Access.Value {
        #if DEBUG
        if notify.frozenDependencies {
            if !containsInvalidation(notify) {
                assertionFailure("Undeclared dependency: \(fieldName) -> \(notify.fieldName)")
            }
        } else {
            addInvalidation(notify)
        }
        #else
        if !notify.frozenDependencies {
            addInvalidation(notify)
        }
        #endif

        return get()
    }

    func addInvalidation(_ field: any InvalidatableField) {
        owner.tree.dependencies.add(field.ref, for: key)
    }

    func removeInvalidation(_ field: any InvalidatableField) {
        owner.tree.dependencies.remove(field.ref, for: key)
    }

    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return owner.tree.dependencies.contains(key, field.ref)
    }

    func setDependencies(_ fields: [any InvalidatableField]) {
        for field in fields {
            field.addInvalidation(self)
        }
        owner.tree.markUsed(self.field, at: owner.id)
        owner.tree.markFrozen(self.field, at: owner.id)
    }
}
