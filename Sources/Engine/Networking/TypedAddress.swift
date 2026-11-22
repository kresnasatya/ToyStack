public struct TypedAddress {
    public let url: WebURL
    let fallback: WebURL?
    let alternate: WebURL?

    init(url: WebURL, fallback: WebURL? = nil, alternate: WebURL? = nil) {
        self.url = url
        self.fallback = fallback
        self.alternate = alternate
    }
}
