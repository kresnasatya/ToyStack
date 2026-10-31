import Foundation

// MARK: - FieldDependencyKey

@MainActor
struct FieldDependencyKey: Hashable {
    let owner: ObjectIdentifier
    let name: FieldName

    init?(_ field: FieldRef) {
        guard let fieldOwner: any FieldOwner = field.owner else { return nil }
        self.owner = ObjectIdentifier(fieldOwner)
        self.name = field.name
    }
}
