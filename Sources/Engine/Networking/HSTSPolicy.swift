import Foundation

/// One `Strict-Transport-Security` header, read per RFC 6797 §6.1.
struct HSTSPolicy: Equatable {
    let maxAge: Int
    let includesSubdomains: Bool

    init(maxAge: Int, includesSubdomains: Bool) {
        self.maxAge = maxAge
        self.includesSubdomains = includesSubdomains
    }

    // RFC 6797 §6.1: directive names ignore case and each may appear only
    // once; §8.1 says a header that breaks the grammar is ignored whole.
    init?(header: String) {
        var directives: [String: String] = [:]
        for part: Substring in header.split(separator: ";", omittingEmptySubsequences: false) {
            let directive: String = part.trimmingCharacters(in: .whitespaces)
            if directive.isEmpty {
                continue
            }
            let pieces: [Substring] = directive.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name: String = pieces[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value: String = pieces.count > 1 ? Self.unquoted(pieces[1]) : ""
            guard directives.updateValue(value, forKey: name) == nil else {
                return nil
            }
        }
        // RFC 6797 §6.1.1: max-age is required and is delta-seconds, digits only.
        guard let rawMaxAge: String = directives["max-age"], !rawMaxAge.isEmpty,
            rawMaxAge.allSatisfy({ (c: Character) -> Bool in c.isASCII && c.isNumber }),
            let maxAge: Int = Int(rawMaxAge)
        else {
            return nil
        }
        self.maxAge = maxAge
        self.includesSubdomains = directives["includesubdomains"] != nil
    }

    private static func unquoted(_ raw: Substring) -> String {
        let value: String = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2 && value.hasPrefix("\"") && value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
