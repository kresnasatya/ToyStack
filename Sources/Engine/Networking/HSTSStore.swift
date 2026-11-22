import Foundation

/// Hosts that asked to be reached over https only (RFC 6797 §8.1).
public actor HSTSStore {
    public static let shared: HSTSStore = HSTSStore()

    private static let preloaded: [String: HSTSEntry] = [
        "dev": HSTSEntry(expires: .distantFuture, includesSubdomains: true),
        "app": HSTSEntry(expires: .distantFuture, includesSubdomains: true),
    ]

    private var entries: [String: HSTSEntry] = [:]
    private var file: URL? = nil

    public func persist(to file: URL) {
        self.file = file
        guard let data: Data = try? Data(contentsOf: file),
            let saved: [String: HSTSEntry] = try? JSONDecoder().decode([String: HSTSEntry].self, from: data)
        else {
            return
        }
        entries.merge(saved, uniquingKeysWith: { (current: HSTSEntry, _: HSTSEntry) -> HSTSEntry in current })
    }

    /// RFC 6797 §8.1: only a header that arrived over https counts, and §8.1.1:
    /// an IP address is never noted as a Known HSTS Host.
    func note(_ header: String, from url: WebURL, now: Date = Date()) {
        guard url.scheme == "https", !IPAddress.isHostLiteral(url.host),
            let policy: HSTSPolicy = HSTSPolicy(header: header)
        else {
            return
        }
        let host: String = url.host.lowercased()
        if policy.maxAge == 0 {
            entries.removeValue(forKey: host)
        } else {
            entries[host] = HSTSEntry(
                expires: now.addingTimeInterval(TimeInterval(policy.maxAge)),
                includesSubdomains: policy.includesSubdomains
            )
        }
        save()
    }

    /// RFC 6797 §8.2 and §8.3 step 5: the host itself matches, and so does any
    /// parent domain whose rule includes subdomains.
    func isKnown(_ host: String, now: Date = Date()) -> Bool {
        let name: String = host.lowercased()
        if rule(for: name, now: now) != nil {
            return true
        }
        var parent: Substring = Substring(name)
        while let dot: Substring.Index = parent.firstIndex(of: ".") {
            parent = parent[parent.index(after: dot)...]
            if let entry: HSTSEntry = rule(for: String(parent), now: now), entry.includesSubdomains {
                return true
            }
        }
        return false
    }

    /// RFC 6797 §8.3 step 5: http becomes https before anything is sent; port 80
    /// becomes 443 and any other port stays.
    func upgrade(_ url: WebURL, now: Date = Date()) -> WebURL {
        guard url.scheme == "http", isKnown(url.host, now: now) else {
            return url
        }
        return WebURL("https://" + url.toString().dropFirst("http://".count))
    }

    private func rule(for host: String, now: Date) -> HSTSEntry? {
        if let entry: HSTSEntry = entries[host] {
            if entry.expires > now {
                return entry
            }
            entries.removeValue(forKey: host)
            save()
        }
        return Self.preloaded[host]
    }

    private func save() {
        guard let file: URL else { return }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            print("Could not save HSTS rules to", file.path, "-", error)
        }
    }
}

// MARK: - HSTSEntry

struct HSTSEntry: Codable {
    let expires: Date
    let includesSubdomains: Bool
}
