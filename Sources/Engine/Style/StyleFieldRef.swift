import Foundation

// MARK: - StyleFieldRef

@MainActor
struct StyleFieldRef: InvalidatableField {
    weak var owner: StyleFields?
    let key: StyleProperty

    var fieldName: String { "style.\(key.cssName)" }
    var dirty: Bool { isDirty }
    var isDirty: Bool { owner?.fieldIsDirty(.style(key)) ?? false }
    var frozenDependencies: Bool { owner?.fieldIsFrozen(.style(key)) ?? false }
    var invalidationNames: [String] { owner?.dependencyNames(.style(key)) ?? [] }
    var ref: FieldRef { FieldRef(owner: owner, name: .style(key)) }

    func touch(_ notify: any InvalidatableField) {
        if notify.frozenDependencies {
            #if DEBUG
            if !containsInvalidation(notify) {
                assertionFailure("Undeclared dependency: \(fieldName) -> \(notify.fieldName)")
            }
            #endif
        } else {
            addInvalidation(notify)
        }
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
