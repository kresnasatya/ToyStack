import Foundation

@MainActor
func layoutFields(of object: any LayoutObject) -> [(String, any InvalidatableField)] {
    var result: [(String, any InvalidatableField)] = []
    var mirror: Mirror? = Mirror(reflecting: object)
    while let current = mirror {
        for child in current.children {
            guard let field = child.value as? any InvalidatableField else { continue }
            result.append((child.label ?? field.fieldName, field))
        }
        mirror = current.superclassMirror
    }
    return result
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
