import Foundation

// MARK: - StyleFieldRef

@MainActor
struct StyleFieldRef: InvalidatableField {
    weak var owner: StyleFields?
    let key: String

    var fieldName: String { "style.\(key)" }
    var dirty: Bool { isDirty }
    var isDirty: Bool { owner?.fieldIsDirty(.style(key)) ?? false }
    var frozenDependencies: Bool { owner?.fieldIsFrozen(.style(key)) ?? false }
    var invalidationNames: [String] { owner?.dependencyNames(.style(key)) ?? [] }
    var ref: FieldRef { FieldRef(owner: owner, name: .style(key)) }

    func read(notify: any InvalidatableField) -> String? {
        if notify.frozenDependencies {
            if !containsInvalidation(notify) {
                assertionFailure("Undeclared dependency: \(fieldName) -> \(notify.fieldName)")
                addInvalidation(notify)
            }
        } else {
            addInvalidation(notify)
        }
        return owner?.values[key]
    }

    func mark() {
        owner?.markField(.style(key))
    }

    func addInvalidation(_ field: any InvalidatableField) {
        owner?.addDependency(.style(key), field.ref)
    }

    func removeInvalidation(_ field: any InvalidatableField) {
        owner?.removeDependency(.style(key), field.ref)
    }

    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return owner?.containsDependency(.style(key), field.ref) ?? false
    }
}
