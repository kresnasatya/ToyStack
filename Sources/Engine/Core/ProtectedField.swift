import Foundation

// MARK: - FieldOwner

@MainActor
struct FieldOwner {
    let name: String
    weak var node: (any DOMNode)?
    weak var parent: (any LayoutObject)?

    init(
        name: String,
        node: (any DOMNode)? = nil,
        parent: (any LayoutObject)? = nil
    ) {
        self.name = name
        self.node = node
        self.parent = parent
    }
}

// MARK: - InvalidatableField

@MainActor
protocol InvalidatableField: AnyObject {
    var fieldName: String { get }
    var isDirty: Bool { get }
    var frozenDependencies: Bool { get }
    var invalidationNames: [String] { get }
    func mark()
    func addInvalidation(_ field: any InvalidatableField)
    func containsInvalidation(_ field: any InvalidatableField) -> Bool
}

// MARK: - ProtectedField

@MainActor
final class ProtectedField<Value>: InvalidatableField {
    private var value: Value?
    private var behavior: FieldBehavior<Value>
    private let owner: FieldOwner
    private(set) var dirty: Bool

    init(
        owner: FieldOwner,
        equals: @escaping (Value, Value) -> Bool
    ) {
        self.owner = owner
        self.behavior = FieldBehavior(equals: equals)
        self.value = nil
        self.dirty = true
        setAncestorDirtyFlags()
    }

    init(
        owner: FieldOwner,
        equals: @escaping (Value, Value) -> Bool,
        cleanValue: Value
    ) {
        self.owner = owner
        self.behavior = FieldBehavior(equals: equals)
        self.value = cleanValue
        self.dirty = false
    }

    var fieldName: String { owner.name }
    var frozenDependencies: Bool { behavior.frozen }
    var isDirty: Bool { dirty }
    var invalidationNames: [String] { behavior.dependencies.names }

    func get() -> Value {
        if dirty {
            assertionFailure("Read dirty field \(self)")
        }
        guard let value else {
            fatalError("Read unset field \(self)")
        }
        return value
    }

    func peek() -> Value? {
        return value
    }

    func set(_ newValue: Value) {
        let changed: Bool
        if let value {
            changed = !behavior.equals(value, newValue)
        } else {
            changed = true
        }
        if changed {
            countLayoutWork("layout.field.set")
            behavior.dependencies.notify()
        }
        value = newValue
        dirty = false
    }

    func mark() {
        if dirty { return }
        countLayoutWork("layout.field.mark")
        dirty = true
        setAncestorDirtyFlags()
    }

    // Style fields have no DOM node; only layout fields report into the
    // layout window. Counting style writes here would mislabel them.
    private func countLayoutWork(_ name: String) {
        guard owner.node != nil else { return }
        profiler.count(name)
    }

    func read(notify: any InvalidatableField) -> Value {
        if notify.frozenDependencies {
            if !containsInvalidation(notify) {
                assertionFailure("Undeclared dependency: \(self) -> \(notify)")
                // Release builds keep the edge so a missed declaration degrades to
                // dynamic discovery instead of a silently stale layout.
                addInvalidation(notify)
            }
        } else {
            addInvalidation(notify)
        }
        return get()
    }

    func copy(from field: ProtectedField<Value>) {
        set(field.read(notify: self))
    }

    // Declares the fields this field depends on and freezes later reads.
    // Calling it again adds inputs; it never removes earlier ones.
    func setDependencies(_ fields: [any InvalidatableField]) {
        for field in fields {
            field.addInvalidation(self)
        }
        behavior.frozen = true
    }

    func addInvalidation(_ field: any InvalidatableField) {
        behavior.dependencies.add(field)
    }

    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return behavior.dependencies.contains(field)
    }

    func setAncestorDirtyFlags() {
        var current: (any LayoutObject)? = owner.parent
        while let object = current, !object.hasDirtyDescendants {
            object.hasDirtyDescendants = true
            current = object.parent
        }
    }
}

extension ProtectedField where Value: Equatable {
    convenience init(
        _ name: String,
        node: (any DOMNode)? = nil,
        parent: (any LayoutObject)? = nil
    ) {
        self.init(
            owner: FieldOwner(name: name, node: node, parent: parent),
            equals: { $0 == $1 }
        )
    }

    convenience init(
        _ name: String,
        cleanValue: Value,
        node: (any DOMNode)? = nil,
        parent: (any LayoutObject)? = nil
    ) {
        self.init(
            owner: FieldOwner(name: name, node: node, parent: parent),
            equals: { $0 == $1 },
            cleanValue: cleanValue
        )
    }
}


extension ProtectedField: @MainActor CustomStringConvertible {
    var description: String {
        let node: String = owner.node.map({ String(describing: $0) }) ?? "-"
        return "ProtectedField(\(node), \(owner.name))"
    }
}

// MARK: - FieldBehavior

@MainActor
private final class FieldBehavior<Value> {
    let equals: (Value, Value) -> Bool
    var dependencies: FieldDependencies = FieldDependencies()
    var frozen: Bool = false

    init(equals: @escaping (Value, Value) -> Bool) {
        self.equals = equals
    }
}

// MARK: - FieldDependencies

@MainActor
private final class FieldDependencies {
    private var fields: [ObjectIdentifier: WeakField] = [:]

    func add(_ field: any InvalidatableField) {
        fields[ObjectIdentifier(field)] = WeakField(field: field)
    }

    func contains(_ field: any InvalidatableField) -> Bool {
        return fields[ObjectIdentifier(field)]?.field != nil
    }

    var names: [String] {
        return fields.values.compactMap({ $0.field?.fieldName }).sorted()
    }

    func notify() {
        var dead: [ObjectIdentifier] = []
        for (key, box) in fields {
            guard let field = box.field else {
                dead.append(key)
                continue
            }
            field.mark()
        }
        for key in dead {
            fields.removeValue(forKey: key)
        }
    }
}

private struct WeakField {
    weak var field: (any InvalidatableField)?
}
