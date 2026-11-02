import Foundation

@MainActor
func layoutFields(of object: LayoutRef) -> [(String, any InvalidatableField)] {
    return LayoutField.allCases
        .filter({ object.tree.isUsed($0, at: object.id) })
        .map({ ($0.rawValue, anyField(object, $0)) })
}

@MainActor
func anyField(_ object: LayoutRef, _ field: LayoutField) -> any InvalidatableField {
    switch field {
    case .children:
        return object.childrenField
    case .previous:
        return object.previousField
    case .font:
        return object.fontField
    case .inlineContent:
        return object.inlineContentField
    default:
        return object.layoutField(field) as LayoutFieldHandle<CGFloatFieldAccess>
    }
}

#if DEBUG
@MainActor
func dumpDependencies(_ object: LayoutRef, indent: Int = 0) {
    let padding: String = String(repeating: "  ", count: indent)
    print("\(padding)\(object.kind) \(String(describing: object.node))")
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
