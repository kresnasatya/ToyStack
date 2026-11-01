import CoreGraphics

// MARK: - LayoutFieldHandle

@MainActor
struct LayoutFieldHandle<Value: LayoutFieldValue>: InvalidatableField {
    unowned let owner: any LayoutObject
    unowned let fields: LayoutFieldStore
    let field: LayoutField

    init(owner: any LayoutObject, fields: LayoutFieldStore, field: LayoutField) {
        self.owner = owner
        self.fields = fields
        self.field = field
    }

    var fieldName: String { field.rawValue }
    var dirty: Bool { isDirty }
    var isDirty: Bool { fields.isDirty(field) }
    var frozenDependencies: Bool { fields.isFrozen(field) }
    var invalidationNames: [String] { fields.dependencyNames(field) }
    var ref: FieldRef { FieldRef(owner: owner, name: .layout(field)) }

    func get() -> Value {
        if fields.isDirty(field) {
            assertionFailure("Read dirty field \(owner).\(field.rawValue)")
        }
        guard fields.isUsed(field) else {
            fatalError("Read unset field \(owner).\(field.rawValue)")
        }
        return fields.value(of: field)
    }

    func peek() -> Value? {
        guard fields.isUsed(field) else { return nil }
        return fields.value(of: field)
    }

    func set(_ newValue: Value) {
        let wasUsed: Bool = fields.isUsed(field)
        let old: Value = fields.value(of: field)
        let changed: Bool = !wasUsed || !Value.equals(old, newValue)
        fields.markUsed(field)
        fields.setValue(of: field, to: newValue)
        fields.markClean(field)
        if changed {
            profiler.count("layout.field.set")
            if fields.hasDependents(field) {
                fields.markDependents(field)
            }
        }
    }

    func setClean(_ newValue: Value) {
        fields.markUsed(field)
        fields.setValue(of: field, to: newValue)
        fields.markClean(field)
    }

    func mark() {
        owner.markField(.layout(field))
    }

    func copy(from field: LayoutFieldHandle<Value>) {
        set(field.read(notify: self))
    }

    func read(notify: any InvalidatableField) -> Value {
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
        fields.addDependent(self.field, field.ref)
    }

    func removeInvalidation(_ field: any InvalidatableField) {
        fields.removeDependent(self.field, field.ref)
    }

    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return fields.containsDependent(self.field, field.ref)
    }

    func setDependencies(_ fields: [any InvalidatableField]) {
        for field in fields {
            field.addInvalidation(self)
        }
        self.fields.markUsed(self.field)
        self.fields.markFrozen(self.field)
    }
}
