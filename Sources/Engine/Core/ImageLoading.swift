// MARK: - ImageLoading
enum ImageLoading {
    case eager
    case lazy

    init(element: Element) {
        self = element.attributes["loading"]?.lowercased() == "lazy" ? .lazy : .eager
    }
}
