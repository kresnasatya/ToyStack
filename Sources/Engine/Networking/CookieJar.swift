import Foundation

// MARK: - CookieJar

/// Cookies by host, each host keeping its cookies in the order they were
/// first set (RFC 6265 §5.4 step 2 lists longer paths first and, among equal
/// paths, older cookies first).
actor CookieJar {
    static let shared: CookieJar = CookieJar()

    private var storage: [String: [Cookie]] = [:]

    func receive(_ setCookie: String, from url: WebURL) {
        for part in Cookie.unfold(setCookie) {
            guard let cookie: Cookie = Cookie(part) else { continue }
            store(cookie, from: url)
        }
    }

    /// `document.cookie = ...` on the page at `url`: one cookie, which may not
    /// touch HttpOnly ones. RFC 6265 §5.3 steps 10 and 11.2: a script can
    /// neither create an HttpOnly cookie nor replace one.
    func receiveFromScript(_ cookieString: String, page url: WebURL) {
        guard let cookie: Cookie = Cookie(cookieString), !cookie.isHTTPOnly else { return }
        if let old: Cookie = live(for: url.host).first(where: { $0.name == cookie.name }), old.isHTTPOnly {
            return
        }
        store(cookie, from: url)
    }

    func header(for url: WebURL, method: String, referrerHost: String?) -> String? {
        let crossSiteWrite: Bool = method != "GET" && referrerHost.map({ $0 != url.host }) ?? false
        let sendable: [Cookie] = visible(at: url).filter({ !(crossSiteWrite && $0.params["samesite"] == "lax") })
        return sendable.isEmpty ? nil : sendable.map(\.pair).joined(separator: "; ")
    }

    func scriptCookies(for url: WebURL) -> String {
        visible(at: url).filter({ !$0.isHTTPOnly }).map(\.pair).joined(separator: "; ")
    }

    // RFC 6265 §5.3 step 11.3: a cookie that replaces one with the same name
    // keeps the old one's creation time, so it keeps its place in the order.
    // draft-ietf-httpbis-rfc6265bis-22 §5.7 steps 13 and 16: from an address
    // that is not secure, a cookie can neither be Secure nor take the place
    // of a Secure one, so an http page cannot plant or overwrite (and so
    // fix) a cookie the https site relies on. Steps 20 and 21: a prefixed
    // name must keep what its prefix promises.
    private func store(_ cookie: Cookie, from url: WebURL) {
        guard cookie.keepsNamePrefixPromise else { return }
        var cookies: [Cookie] = live(for: url.host)
        let index: Int? = cookies.firstIndex(where: { $0.name == cookie.name })
        if !Self.isSecure(url) {
            guard !cookie.isSecure else { return }
            if let index: Int, cookies[index].isSecure { return }
        }
        if let index: Int {
            cookies[index] = cookie
        } else {
            cookies.append(cookie)
        }
        storage[url.host] = cookies
    }

    // RFC 6265 §5.4 step 1: a Secure cookie is sent only when the request's scheme is
    // secure. `document.cookie` applies the same rule to the page's scheme.
    private func visible(at url: WebURL) -> [Cookie] {
        let isSecureScheme: Bool = Self.isSecure(url)
        return live(for: url.host).filter({ isSecureScheme || !$0.isSecure })
    }

    private static func isSecure(_ url: WebURL) -> Bool {
        url.scheme == "https"
    }

    private func live(for host: String, now: Date = Date()) -> [Cookie] {
        let cookies: [Cookie] = (storage[host] ?? []).filter({ !$0.isExpired(at: now) })
        storage[host] = cookies.isEmpty ? nil : cookies
        return cookies
    }
}
