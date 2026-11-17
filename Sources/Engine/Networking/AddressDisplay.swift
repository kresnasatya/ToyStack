/// The shorter address the toolbar shows while the user is not editing it.
/// Chrome drops "https://", a leading "www." and a lone "/" path; http
/// addresses stay whole so the scheme next to "Not Secure" is visible.
public enum AddressDisplay {
    private static let securePrefix: String = "https://"
    private static let wwwPrefix: String = "www."

    public static func text(for url: WebURL) -> String {
        let full: String = url.toString()
        guard url.scheme == "https", full.hasPrefix(securePrefix) else {
            return full
        }
        var shown: Substring = full.dropFirst(securePrefix.count)
        if shown.hasPrefix(wwwPrefix) {
            let rest: Substring = shown.dropFirst(wwwPrefix.count)
            let hostAfterWWW: Substring = rest.prefix(while: { (c: Character) -> Bool in c != "/" && c != ":" })
            if hostAfterWWW.contains(".") {
                shown = rest
            }
        }
        if url.path == "/" && url.fragment == nil && shown.hasSuffix("/") {
            shown = shown.dropLast()
        }
        return String(shown)
    }
}
