import Foundation

public enum AddressInput {
    private static let schemePrefixes: [String] = [
        "http://", "https://", "file://", "about:", "view-source:", "data:",
    ]
    private static let searchPrefix: String = "https://google.com/search?q="
    private static let queryWordCharacters: CharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
    private static let pathStarts: Set<Character> = ["/", "?", "#"]

    public static func address(for typed: String) -> TypedAddress? {
        let input: String = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            return nil
        }
        if schemePrefixes.contains(where: { (prefix: String) -> Bool in input.hasPrefix(prefix) }) {
            return TypedAddress(url: WebURL(input))
        }
        if input.hasPrefix("?") {
            return search(String(input.dropFirst()))
        }
        if let address: TypedAddress = fixedUpAddress(input) {
            return address
        }
        return search(input, alternate: machineAddress(input))
    }

    private static func fixedUpAddress(_ input: String) -> TypedAddress? {
        if input.contains(where: { (c: Character) -> Bool in c.isWhitespace || c == "@" }) {
            return nil
        }
        let pathStart: String.Index =
            input.firstIndex(where: { (c: Character) -> Bool in pathStarts.contains(c) }) ?? input.endIndex
        guard let host: TypedHost = TypedHost(input[input.startIndex..<pathStart]) else {
            return nil
        }
        let rest: Substring = input[pathStart...]
        let typedAsAddress: Bool = host.port != nil || rest.hasPrefix("/")
        guard host.kind.isAlwaysAddress || typedAsAddress else {
            return nil
        }
        let port: String = host.port.map({ (port: Int) -> String in ":\(port)" }) ?? ""
        let path: String = rest.hasPrefix("/") ? String(rest) : "/" + rest
        let plain: WebURL = WebURL("http://\(host.name)\(port)\(path)")
        guard host.kind.usesHTTPS else {
            return TypedAddress(url: plain)
        }
        return TypedAddress(url: WebURL("https://\(host.name)\(port)\(path)"), fallback: plain)
    }

    private static func machineAddress(_ input: String) -> WebURL? {
        guard let host: TypedHost = TypedHost(Substring(input)), host.kind == .singleLabel else {
            return nil
        }
        return WebURL("http://\(host.name)/")
    }

    private static func search(_ text: String, alternate: WebURL? = nil) -> TypedAddress? {
        let query: String = searchQuery(text)
        if query.isEmpty {
            return nil
        }
        return TypedAddress(url: WebURL(searchPrefix + query), alternate: alternate)
    }

    private static func searchQuery(_ text: String) -> String {
        let words: [String] = text.split(whereSeparator: { (c: Character) -> Bool in c.isWhitespace }).map {
            (word: Substring) -> String in
            word.addingPercentEncoding(withAllowedCharacters: queryWordCharacters) ?? ""
        }
        return words.joined(separator: "+")
    }
}

// MARK: - TypedHost

private struct TypedHost {
    enum Kind {
        case ipAddress
        case local
        case singleLabel
        case knownDomain
        case unknownDomain

        var isAlwaysAddress: Bool {
            switch self {
            case .ipAddress, .local, .knownDomain: return true
            case .singleLabel, .unknownDomain: return false
            }
        }

        var usesHTTPS: Bool {
            switch self {
            case .knownDomain, .unknownDomain: return true
            case .ipAddress, .local, .singleLabel: return false
            }
        }
    }

    private static let labelCharacters: CharacterSet = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_"
    )

    let name: String
    let port: Int?
    let kind: Kind

    init?(_ authority: Substring) {
        guard let (host, port): (Substring, Int?) = Self.splitPort(authority), !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("[") {
            let inside: String = String(host.dropFirst().dropLast())
            guard IPAddress.isV6(inside) else {
                return nil
            }
            name = "[\(inside.lowercased())]"
            kind = .ipAddress
        } else {
            guard let ascii: String = Self.asciiName(host) else {
                return nil
            }
            name = ascii
            kind = Self.kind(of: ascii)
        }
        self.port = port
    }

    private static func splitPort(_ authority: Substring) -> (Substring, Int?)? {
        var host: Substring = authority
        var portText: Substring? = nil
        if authority.hasPrefix("[") {
            guard let close: Substring.Index = authority.firstIndex(of: "]") else {
                return nil
            }
            host = authority[...close]
            let after: Substring = authority[authority.index(after: close)...]
            if !after.isEmpty {
                guard after.hasPrefix(":") else {
                    return nil
                }
                portText = after.dropFirst()
            }
        } else if let colon: Substring.Index = authority.firstIndex(of: ":") {
            host = authority[..<colon]
            portText = authority[authority.index(after: colon)...]
        }
        guard let portText: Substring else {
            return (host, nil)
        }
        guard portText.allSatisfy({ (c: Character) -> Bool in c.isASCII && c.isNumber }),
            let port: Int = Int(portText), (1...65535).contains(port)
        else {
            return nil
        }
        return (host, port)
    }

    // RFC 3490 §4.1 ToASCII: labels with letters outside ASCII travel as "xn--" plus their
    // Punycode form, and step 3 (UseSTD3ASCIIRules) keeps "-" off both ends of a label.
    private static func asciiName(_ host: Substring) -> String? {
        let normalized: String = String(host).precomposedStringWithCanonicalMapping.lowercased()
        var labels: [String] = []
        for label: Substring in normalized.split(separator: ".", omittingEmptySubsequences: false) {
            guard !label.isEmpty, !label.hasPrefix("-"), !label.hasSuffix("-") else {
                return nil
            }
            let scalars: Substring.UnicodeScalarView = label.unicodeScalars
            guard scalars.allSatisfy({ (s: Unicode.Scalar) -> Bool in !s.isASCII || labelCharacters.contains(s) }) else {
                return nil
            }
            let isASCII: Bool = scalars.allSatisfy({ (s: Unicode.Scalar) -> Bool in s.isASCII })
            labels.append(isASCII ? String(label) : "xn--" + Punycode.encode(String(label)))
        }
        return labels.joined(separator: ".")
    }

    private static func kind(of name: String) -> Kind {
        if IPAddress.isV4(name) {
            return .ipAddress
        }
        if name == "localhost" || name.hasSuffix(".localhost") {
            return .local
        }
        guard let lastDot: String.Index = name.lastIndex(of: ".") else {
            return .singleLabel
        }
        let topLevel: String = String(name[name.index(after: lastDot)...])
        return TopLevelDomains.contains(topLevel) ? .knownDomain : .unknownDomain
    }
}
