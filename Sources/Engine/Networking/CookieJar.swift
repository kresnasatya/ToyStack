import Foundation

// MARK: - CookieJar

actor CookieJar {
    static let shared: CookieJar = CookieJar()

    private var storage: [String: (cookie: String, params: [String: String], expires: Date?)] = [:]

    func get(_ host: String) -> (String, [String: String])? {
        guard let entry = storage[host] else { return nil }
        if let expires = entry.expires, Date() > expires {
            storage.removeValue(forKey: host)
            return nil
        }
        return (entry.cookie, entry.params)
    }

    func set(_ host: String, cookie: String, params: [String: String]) {
        var expires: Date? = nil
        if let maxAge = params["max-age"], let seconds = Double(maxAge) {
            expires = Date().addingTimeInterval(seconds)
        } else if let expiresStr = params["expires"] {
            let formatter: DateFormatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            expires = formatter.date(from: expiresStr)
        }
        storage[host] = (cookie: cookie, params: params, expires: expires)
    }

    /// Stores the cookie from one response's `Set-Cookie` header under the
    /// host that sent it.
    func receive(_ setCookie: String, from host: String) {
        var cookie: String = setCookie
        var params: [String: String] = [:]
        if cookie.contains(";") {
            let parts: [String.SubSequence] = cookie.split(separator: ";", maxSplits: 1)
            cookie = String(parts[0])
            if parts.count > 1 {
                for param in String(parts[1]).split(separator: ";") {
                    let trimmed: String = param.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("=") {
                        let kv: [String.SubSequence] = trimmed.split(separator: "=", maxSplits: 1)
                        params[String(kv[0]).lowercased()] = String(kv[1]).lowercased()
                    } else {
                        params[trimmed.lowercased()] = "true"
                    }
                }
            }
        }
        set(host, cookie: cookie, params: params)
    }

    /// The `Cookie` header for a request to `host`, or nil when none may be sent.
    /// A SameSite=Lax cookie stays home when another site's page sends a
    /// non-GET request.
    func header(for host: String, method: String, referrerHost: String?) -> String? {
        guard let (cookie, params): (String, [String: String]) = get(host) else { return nil }
        if let referrerHost, params["samesite"] == "lax", method != "GET", host != referrerHost {
            return nil
        }
        return cookie
    }
}
