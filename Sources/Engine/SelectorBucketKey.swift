import Foundation

enum SelectorBucketKey {
    case tag(String)
    case className(String)
    case id(String)
    case universal

    var rank: Int {
        switch self {
            case .id: return 3
            case .className: return 2
            case .tag: return 1
            case .universal: return 0
        }
    }
}
