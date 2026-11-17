import Darwin

enum IPAddress {
    static func isV4(_ text: String) -> Bool {
        parses(text, family: AF_INET)
    }

    static func isV6(_ text: String) -> Bool {
        parses(text, family: AF_INET6)
    }

    /// A host as it appears in a URL: IPv6 sits inside brackets.
    static func isHostLiteral(_ host: String) -> Bool {
        if host.hasPrefix("[") && host.hasSuffix("]") {
            return isV6(String(host.dropFirst().dropLast()))
        }
        return isV4(host)
    }

    private static func parses(_ text: String, family: Int32) -> Bool {
        var address: in6_addr = in6_addr()
        return inet_pton(family, text, &address) == 1
    }
}
