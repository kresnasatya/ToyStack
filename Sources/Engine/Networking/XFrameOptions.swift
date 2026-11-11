import Foundation

// MARK: - XFrameOptions

enum XFrameOptions {
    case none
    case deny
    case sameOrigin

    init(header: String?) {
        let value: String = header?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch value {
        case "deny":
            self = .deny
        case "sameorigin":
            self = .sameOrigin
        default:
            self = .none
        }
    }

    func allowsEmbedding(documentOrigin: String, ancestorOrigins: [String]) -> Bool {
        switch self {
        case .none:
            return true
        case .deny:
            return false
        case .sameOrigin:
            return ancestorOrigins.allSatisfy({ $0 == documentOrigin })
        }
    }
}
