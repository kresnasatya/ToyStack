import Foundation

#if DEBUG
@MainActor
func dumpDependencies(_ object: LayoutRef, indent: Int = 0) {
    let padding: String = String(repeating: "  ", count: indent)
    print("\(padding)\(object.kind) \(String(describing: object.node))")
    for field in LayoutField.allCases where object.tree.isUsed(field, at: object.id) {
        let inputs: String = LayoutInputTable
            .inputs(for: object.id, field: field, in: object.tree)
            .map({ $0.description })
            .sorted()
            .joined(separator: ", ")
        let dirty: Bool = object.tree.isDirty(field, at: object.id)
        print("\(padding)  \(field.rawValue) dirty=\(dirty) inputs=[\(inputs)]")
    }
    for child in object.children {
        dumpDependencies(child, indent: indent + 1)
    }
}
#endif
