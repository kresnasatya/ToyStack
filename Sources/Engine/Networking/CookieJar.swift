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
}
