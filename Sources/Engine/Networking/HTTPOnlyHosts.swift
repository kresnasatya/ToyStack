import Foundation

/// Hosts whose guessed https failed, so the next typed visit goes straight
/// to http instead of waiting for the same failure again.
actor HTTPOnlyHosts {
    static let shared: HTTPOnlyHosts = HTTPOnlyHosts()

    /// Long enough to stop retrying a broken site on every visit, short enough
    /// that a site which later adds https gets used over https.
    private static let memory: TimeInterval = 7 * 24 * 60 * 60

    private var expiries: [String: Date] = [:]

    func remember(_ host: String, now: Date = Date()) {
        expiries[host.lowercased()] = now.addingTimeInterval(Self.memory)
    }

    func contains(_ host: String, now: Date = Date()) -> Bool {
        let name: String = host.lowercased()
        guard let expiry: Date = expiries[name] else { return false }
        if expiry > now {
            return true
        }
        expiries.removeValue(forKey: name)
        return false
    }

    func forget(_ host: String) {
        expiries.removeValue(forKey: host.lowercased())
    }
}
