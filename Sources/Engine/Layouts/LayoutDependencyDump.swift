import Foundation

#if DEBUG
@MainActor
func dumpDependencies(_ tree: LayoutTree, _ id: LayoutID, indent: Int = 0) {
    let padding: String = String(repeating: "  ", count: indent)
    print("\(padding)\(tree.kind(id)) \(String(describing: tree.domRef(id)))")
    for field in LayoutField.allCases where tree.isUsed(field, at: id) {
        let inputs: String = LayoutInputTable
            .inputs(for: id, field: field, in: tree)
            .map({ $0.description })
            .sorted()
            .joined(separator: ", ")
        let dirty: Bool = tree.isDirty(field, at: id)
        print("\(padding)  \(field.rawValue) dirty=\(dirty) inputs=[\(inputs)]")
    }
    for child in tree.childrenIDs(of: id) {
        dumpDependencies(tree, child, indent: indent + 1)
    }
}
#endif
