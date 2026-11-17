import Darwin
import Foundation

public enum HostLookup {
    /// Asks the system resolver (DNS, /etc/hosts, mDNS) whether the name has
    /// an address. getaddrinfo blocks, so it runs off the caller's thread.
    public static func exists(_ host: String) async -> Bool {
        guard !host.isEmpty else { return false }
        return await Task.detached(priority: .utility, operation: { () -> Bool in
            var hints: addrinfo = addrinfo()
            hints.ai_socktype = SOCK_STREAM
            var results: UnsafeMutablePointer<addrinfo>? = nil
            let status: Int32 = getaddrinfo(host, nil, &hints, &results)
            if let results {
                freeaddrinfo(results)
            }
            return status == 0
        }).value
    }
}
