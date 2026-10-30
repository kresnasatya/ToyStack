import Foundation

@MainActor
func layoutFields(of object: any LayoutObject) -> [(String, any InvalidatableField)] {
    return LayoutField.allCases
        .filter({ object.fields.isUsed($0) })
        .map({ ($0.rawValue, object.fieldRef($0) )})
}

#if DEBUG
@MainActor
func dumpDependencies(_ object: any LayoutObject, indent: Int = 0) {
    let padding: String = String(repeating: "  ", count: indent)
    print("\(padding)\(type(of: object)) \(String(describing: object.node))")
    for (name, field) in layoutFields(of: object) {
        let state: String = field.frozenDependencies ? "frozen" : "dynamic"
        let invalidations: String = field.invalidationNames.joined(separator: ", ")
        print(
            "\(padding)  \(name) [\(state)] dirty=\(field.isDirty) invalidates=[\(invalidations)]"
        )
    }
    for child in object.children {
        dumpDependencies(child, indent: indent + 1)
    }
}
#endif
