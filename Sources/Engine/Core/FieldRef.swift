import Foundation

// MARK: - FieldKey description

extension FieldKey {
    var description: String {
        switch self {
        case .layout(_, let field):
            return field.rawValue
        case .style(_, let key):
            return "style.\(key.cssName)"
        }
    }
}

// MARK: - InvalidatableField

@MainActor
protocol InvalidatableField {
    var fieldKey: FieldKey { get }
    var fieldName: String { get }
    var isDirty: Bool { get }
    var frozenDependencies: Bool { get }
    var invalidationNames: [String] { get }
    var ref: FieldRef { get }

    func mark()
    func addInvalidation(_ field: any InvalidatableField)
    func removeInvalidation(_ field: any InvalidatableField)
    func containsInvalidation(_ field: any InvalidatableField) -> Bool
}

// MARK: - FieldRef

/// A dependency edge target: the field's key plus the action that dirties it.
///
/// Storing a key and a closure instead of an owner object lets a layout node
/// (a struct view over the arena) be an invalidation target without keeping a
/// class pointer alive.
@MainActor
struct FieldRef: InvalidatableField {
    let fieldKey: FieldKey
    let markBody: () -> Void
    let aliveBody: () -> Bool

    init(
        key: FieldKey,
        markBody: @escaping () -> Void,
        isAlive: @escaping () -> Bool = { true }
    ) {
        self.fieldKey = key
        self.markBody = markBody
        self.aliveBody = isAlive
    }

    var isAlive: Bool { aliveBody() }

    var fieldName: String { fieldKey.description }
    var isDirty: Bool { false }
    var frozenDependencies: Bool { true }
    var invalidationNames: [String] { [] }
    var ref: FieldRef { self }

    func mark() {
        markBody()
    }

    func addInvalidation(_ field: any InvalidatableField) {}
    func removeInvalidation(_ field: any InvalidatableField) {}
    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return false
    }
}
