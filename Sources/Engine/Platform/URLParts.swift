import Foundation

// MARK: - URLParts

enum URLParts {
    // URL Standard §6.1 "URL class": a URL that cannot be parsed makes the constructor
    // throw, so an unparseable input gives no parts at all.
    static func parse(_ input: String, base: String) -> [String: String] {
        guard let url: WebURL = resolve(input, base: base) else { return [:] }
        let defaultPort: Int = url.scheme == "https" ? 443 : (url.scheme == "http" ? 80 : 0)
        let port: String = url.port == defaultPort ? "" : String(url.port)
        let host: String = port.isEmpty ? url.host : url.host + ":" + port
        let queryStart: String.Index = url.path.firstIndex(of: "?") ?? url.path.endIndex
        let search: String = String(url.path[queryStart...])
        let fragment: String = url.fragment ?? ""
        let isHTTP: Bool = url.scheme == "http" || url.scheme == "https"
        return [
            "href": url.toString(),
            "protocol": url.scheme + ":",
            "host": host,
            "hostname": url.host,
            "port": port,
            "pathname": String(url.path[..<queryStart]),
            "search": search == "?" ? "" : search,
            "hash": fragment.isEmpty ? "" : "#" + fragment,
            "origin": isHTTP ? url.scheme + "://" + host : "null",
        ]
    }

    // URL Standard §4.4 "scheme state": an input that starts with its own scheme ("mailto:",
    // "https:") is parsed on its own. The spec still resolves a special scheme equal to the
    // base's ("https:foo" on an https page) against the base; this resolver does not.
    private static func resolve(_ input: String, base: String) -> WebURL? {
        if base.isEmpty || hasScheme(input) { return loadable(input) }
        guard let baseURL: WebURL = loadable(base) else { return nil }
        let resolved: WebURL = baseURL.resolve(input)
        return resolved.scheme == "about" ? nil : resolved
    }

    private static func loadable(_ input: String) -> WebURL? {
        let url: WebURL = WebURL(input)
        return url.scheme == "about" && !input.hasPrefix("about:") ? nil : url
    }

    // URL Standard §4.4 "scheme start state" and "scheme state": an ASCII letter, then
    // ASCII letters, digits, "+", "-" or ".", then ":".
    private static func hasScheme(_ input: String) -> Bool {
        guard let colon: String.Index = input.firstIndex(of: ":") else { return false }
        let scheme: Substring = input[input.startIndex..<colon]
        guard let first: Character = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy({ (c: Character) -> Bool in
            c.isASCII && (c.isLetter || c.isNumber || c == "+" || c == "-" || c == ".")
        })
    }
}
