import Foundation

// MARK: - StyleFieldRef

@MainActor
struct StyleFieldRef: InvalidatableField {
    weak var owner: StyleFields?
    let property: StyleProperty

    var fieldKey: FieldKey {
        let node: NodeID = owner?.owner ?? NodeID(raw: 0)
        return .style(node, property)
    }

    var fieldName: String { "style.\(property.cssName)" }
    var dirty: Bool { isDirty }
    var isDirty: Bool { owner?.fieldIsDirty(property) ?? false }
    var frozenDependencies: Bool { false }
    var invalidationNames: [String] { owner?.dependencyNames(property) ?? [] }
    var ref: FieldRef {
        let style: StyleFields? = owner
        let key: StyleProperty = property
        return FieldRef(
            key: fieldKey,
            markBody: { [weak style] in
                style?.markStyle(key)
            },
            isAlive: { [weak style] in
                style?.owner != nil
            }
        )
    }

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
        owner?.markStyle(property)
    }

    func addInvalidation(_ field: any InvalidatableField) {
        owner?.addDependency(property, field.ref)
    }

    func removeInvalidation(_ field: any InvalidatableField) {
        owner?.removeDependency(property, field.ref)
    }

    func containsInvalidation(_ field: any InvalidatableField) -> Bool {
        return owner?.containsDependency(property, field.ref) ?? false
    }
}
