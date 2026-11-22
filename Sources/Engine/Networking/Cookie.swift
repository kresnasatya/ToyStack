import Foundation

/// One stored cookie (RFC 6265 §5.3). `params` keeps each attribute under its
/// lowercased name with a lowercased value; a flag such as HttpOnly is "true".
struct Cookie {
    let name: String
    let value: String
    let params: [String: String]
    let expires: Date?

    /// RFC 6265 §5.2 steps 2 and 5: a set-cookie-string without "=" or with
    /// an empty name is ignored.
    init?(_ setCookie: String, now: Date = Date()) {
        let parts: [Substring] = setCookie.split(separator: ";", omittingEmptySubsequences: false)
        guard let pair: Substring = parts.first, let equals: Substring.Index = pair.firstIndex(of: "=") else { return nil }
        let name: String = pair[pair.startIndex..<equals].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }

        var params: [String: String] = [:]
        var rawExpires: String? = nil
        for attribute in parts.dropFirst() {
            let nameAndValue: [Substring] = attribute.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key: String = nameAndValue[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            guard nameAndValue.count == 2 else {
                params[key] = "true"
                continue
            }
            let rawValue: String = nameAndValue[1].trimmingCharacters(in: .whitespaces)
            if key == "expires" { rawExpires = rawValue }
            params[key] = rawValue.lowercased()
        }

        self.name = name
        self.value = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        self.params = params
        self.expires = Self.expiry(maxAge: params["max-age"], expires: rawExpires, now: now)
    }

    var pair: String { "\(name)=\(value)" }

    var isHTTPOnly: Bool { params["httponly"] != nil }

    var isSecure: Bool { params["secure"] != nil }

    func isExpired(at now: Date) -> Bool {
        guard let expires: Date else { return false }
        return expires <= now
    }

    // RFC 6265 §5.3 step 3: Max-Age wins over Expires when both are present.
    private static func expiry(maxAge: String?, expires: String?, now: Date) -> Date? {
        if let maxAge: String, let seconds: Double = Double(maxAge) {
            return now.addingTimeInterval(seconds)
        }
        guard let expires: String else { return nil }
        let formatter: DateFormatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: expires)
    }
}

// MARK: - Folded Set-Cookie

extension Cookie {
    /// Foundation joins repeated Set-Cookie fields into one with ", ", the
    /// folding RFC 6265 §3 warns breaks cookies because Expires dates hold a
    /// comma too. A comma starts a new cookie only when a `name=` follows it
    /// before the next ";"; the comma in "Wed, 21 Oct 2026" is followed by none.
    static func unfold(_ header: String) -> [String] {
        var cookies: [String] = []
        for piece in header.split(separator: ",", omittingEmptySubsequences: false) {
            if cookies.isEmpty || startsCookie(piece) {
                cookies.append(String(piece))
            } else {
                cookies[cookies.count - 1] += "," + piece
            }
        }
        return cookies
    }

    private static func startsCookie(_ piece: Substring) -> Bool {
        let firstPart: Substring = piece.prefix(while: { $0 != ";" })
        guard let equals: Substring.Index = firstPart.firstIndex(of: "=") else { return false }
        let name: String = firstPart[firstPart.startIndex..<equals].trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !name.contains(" ")
    }
}
