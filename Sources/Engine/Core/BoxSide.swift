// MARK: - BoxSide

enum BoxSide: Int, CaseIterable {
    case top
    case right
    case bottom
    case left

    var next: BoxSide {
        switch self {
        case .top: return .right
        case .right: return .bottom
        case .bottom: return .left
        case .left: return .top
        }
    }

    var previous: BoxSide {
        switch self {
        case .top: return .left
        case .right: return .top
        case .bottom: return .right
        case .left: return .bottom
        }
    }
}
