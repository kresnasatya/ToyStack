// MARK: - ImageLoading
enum ImageLoading {
    case eager
    case lazy

    @MainActor
    init(element: ElementRef) {
        self = element.attributes["loading"]?.lowercased() == "lazy" ? .lazy : .eager
    }
}
