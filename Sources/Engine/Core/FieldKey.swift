import Foundation

enum FieldKey: Hashable {
    case layout(LayoutID, LayoutField)
    case style(NodeID, StyleProperty)
}

extension FieldKey {
    var description: String {
        switch self {
        case .layout(_, let field):
            return field.rawValue
        case .style(_, let key):
            return "style.\(key.cssName)"
        }
    }
}
