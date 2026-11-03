// MARK: - ImageLoading
enum ImageLoading {
    case eager
    case lazy

    init(attributes: [String: String]) {
        self = attributes["loading"]?.lowercased() == "lazy" ? .lazy : .eager
    }
}
