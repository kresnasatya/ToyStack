import Foundation

// MARK: - FieldName

@MainActor
enum FieldName: Hashable {
    case layout(LayoutField)
    case style(String)

    var description: String {
        switch self {
        case .layout(let field):
            return field.rawValue
        case .style(let key):
            return "style.\(key)"
        }
    }
}

// MARK: - InvalidatableField

@MainActor
protocol InvalidatableField {
    var fieldName: String { get }
    var isDirty: Bool { get }
    var frozenDependencies: Bool { get }
    var invalidationNames: [String] { get }
    var ref: FieldRef { get }

    func mark()
    func addInvalidation(_ field: any InvalidatableField)
    func containsInvalidation(_ field: any InvalidatableField) -> Bool
}

// MARK: - FieldOwner

@MainActor
protocol FieldOwner: AnyObject {
    func markField(_ name: FieldName)
    func addDependency(_ name: FieldName, _ field: FieldRef)
    func containsDependency(_ name: FieldName, _ field: FieldRef) -> Bool
    func fieldIsDirty(_ name: FieldName) -> Bool
    func fieldIsFrozen(_ name: FieldName) -> Bool
    func dependencyNames(_ name: FieldName) -> [String]
}

// MARK: - FieldRef

@MainActor
struct FieldRef: InvalidatableField {
    weak var owner: (any FieldOwner)?
    let name: FieldName

    var fieldName: String { name.description }
    var isDirty: Bool { owner?.fieldIsDirty(name) ?? false }
    var frozenDependencies: Bool { owner?.fieldIsFrozen(name) ?? false }
    var invalidationNames: [String] { owner?.dependencyNames(name) ?? [] }
    var ref: FieldRef { self }

    func mark() {
        owner?.markField(name)
    }

    func addInvalidation(_ field: any InvalidatableField) {
        owner?.addDependency(name, field.ref)
    }

    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return owner?.containsDependency(name, field.ref) ?? false
    }

    func sameTarget(as other: FieldRef) -> Bool {
        return owner === other.owner && name == other.name
    }
}
