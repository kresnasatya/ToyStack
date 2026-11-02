// MARK: - ObjectFitKind

enum ObjectFitKind: Equatable {
    case fill
    case contain
    case cover
    case none
    case scaleDown

    init(css: String?) {
        switch css?.lowercased() {
        case "contain": self = .contain
        case "cover": self = .cover
        case "none": self = .none
        case "scale-down": self = .scaleDown
        default: self = .fill
        }
    }
}
