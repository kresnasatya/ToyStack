public struct TypedAddress {
    public let url: WebURL
    /// The same address over http, tried only when https was a guess and the
    /// secure connection could not be made.
    let fallback: WebURL?

    init(url: WebURL, fallback: WebURL? = nil) {
        self.url = url
        self.fallback = fallback
    }
}
