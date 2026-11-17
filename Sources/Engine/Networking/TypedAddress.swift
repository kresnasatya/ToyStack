public struct TypedAddress {
    public let url: WebURL
    /// The same address over http, tried only when https was a guess and the
    /// secure connection could not be made.
    let fallback: WebURL?
    /// A single word is searched, but it may also name a machine on the local
    /// network; this is that machine's address, offered if it exists.
    let alternate: WebURL?

    init(url: WebURL, fallback: WebURL? = nil, alternate: WebURL? = nil) {
        self.url = url
        self.fallback = fallback
        self.alternate = alternate
    }
}
