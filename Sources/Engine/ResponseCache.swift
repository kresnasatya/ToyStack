import Foundation

struct HttpResponse {
    let status: Int
    let headers: [String: String]
    let content: String
}

// MARK: - CacheEntry

struct CacheEntry {
    let status: Int
    let headers: [String: String]
    let content: String
    let timestamp: Date
    let maxAge: Int

    init(_ response: HttpResponse, maxAge: Int, now: Date = Date()) {
        self.status = response.status
        self.headers = response.headers
        self.content = response.content
        self.timestamp = now
        self.maxAge = maxAge
    }
}

// MARK: - ResponseCache

actor ResponseCache {
    static let shared = ResponseCache()

    private var storage: [String: CacheEntry] = [:]

    func get(_ url: String) -> (status: Int, headers: [String: String], content: String)? {
        guard let entry = storage[url] else { return nil }
        if entry.maxAge >= 0 {
            let age = Date().timeIntervalSince(entry.timestamp)
            if age > Double(entry.maxAge) {
                storage.removeValue(forKey: url)
                return nil
            }
        }

        return (entry.status, entry.headers, entry.content)
    }

    func set(_ url: String, status: Int, headers: [String: String], content: String, maxAge: Int) {
        storage[url] = CacheEntry(
            HttpResponse(status: status, headers: headers, content: content),
            maxAge: maxAge
        )
    }
}
