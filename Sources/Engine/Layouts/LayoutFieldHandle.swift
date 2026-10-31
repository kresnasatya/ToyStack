import CoreGraphics

// MARK: - LayoutFieldHandle

@MainActor
struct LayoutFieldHandle<Value>: InvalidatableField {
    weak var owner: (any LayoutObject)?
    let field: LayoutField
    let valuePath: WritableKeyPath<LayoutFieldStore, Value>
    let equals: (Value, Value) -> Bool

    var fieldName: String { field.rawValue }
    var dirty: Bool { isDirty }
    var isDirty: Bool { owner?.fields.isDirty(field) ?? false }
    var frozenDependencies: Bool { owner?.fields.isFrozen(field) ?? false }
    var invalidationNames: [String] { owner?.fields.dependencyNames(field) ?? [] }
    var ref: FieldRef { FieldRef(owner: owner, name: .layout(field)) }

    func get() -> Value {
        guard let owner else {
            fatalError("Read detached field \(field.rawValue)")
        }
        if owner.fields.isDirty(field) {
            assertionFailure("Read dirty field \(owner).\(field.rawValue)")
        }
        guard owner.fields.isUsed(field) else {
            fatalError("Read unset field \(owner).\(field.rawValue)")
        }
        return owner.fields[keyPath: valuePath]
    }

    func peek() -> Value? {
        guard let owner, owner.fields.isUsed(field) else { return nil }
        return owner.fields[keyPath: valuePath]
    }

    func set(_ newValue: Value) {
        guard let owner else { return }
        let wasUsed: Bool = owner.fields.isUsed(field)
        let old: Value = owner.fields[keyPath: valuePath]
        let changed: Bool = !wasUsed || !equals(old, newValue)
        var fields: LayoutFieldStore = owner.fields
        fields.markUsed(field)
        fields[keyPath: valuePath] = newValue
        fields.markClean(field)
        let dependents: [FieldRef] = fields.takeDependents(field)
        owner.fields = fields
        if changed {
            profiler.count("layout.field.set")
            for dependent in dependents {
                dependent.mark()
            }
        }
    }

    func setClean(_ newValue: Value) {
        guard let owner else { return }
        owner.fields.markUsed(field)
        owner.fields[keyPath: valuePath] = newValue
        owner.fields.markClean(field)
    }

    func mark() {
        owner?.markField(.layout(field))
    }

    func copy(from field: LayoutFieldHandle<Value>) {
        set(field.read(notify: self))
    }

    func read(notify: any InvalidatableField) -> Value {
        if notify.frozenDependencies {
            if !containsInvalidation(notify) {
                assertionFailure("Undeclared dependency: \(fieldName) -> \(notify.fieldName)")
                addInvalidation(notify)
            }
        } else {
            addInvalidation(notify)
        }
        return get()
    }

    func addInvalidation(_ field: any InvalidatableField) {
        owner?.fields.addDependent(self.field, field.ref)
    }

    func removeInvalidation(_ field: any InvalidatableField) {
        owner?.removeDependency(.layout(self.field), field.ref)
    }

    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return owner?.fields.containsDependent(self.field, field.ref) ?? false
    }

    func setDependencies(_ fields: [any InvalidatableField]) {
        for field in fields {
            field.addInvalidation(self)
        }
        owner?.fields.markUsed(self.field)
        owner?.fields.markFrozen(self.field)
    }
}
