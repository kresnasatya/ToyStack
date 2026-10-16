import Foundation

// MARK: - XFrameOptions

enum XFrameOptions {
    // No header, or a value this browser does not recognize. Framing allowed.
    case none
    // `DENY`: the document may never be shown inside a frame.
    case deny
    // `SAMEORIGIN`: the document may be shown only when every frame that
    // contains it came from the document's own origin.
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
