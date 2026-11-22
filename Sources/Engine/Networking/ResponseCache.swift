import Foundation

struct CacheResponse {
    let status: Int
    let headers: [String: String]
    let content: String
    let redirectedTo: String?
}

// MARK: - CacheEntry

struct CacheEntry {
    let response: CacheResponse
    let timestamp: Date
    let maxAge: Int

    init(_ response: CacheResponse, maxAge: Int, now: Date = Date()) {
        self.response = response
        self.timestamp = now
        self.maxAge = maxAge
    }
}

// MARK: - ResponseCache

actor ResponseCache {
    static let shared: ResponseCache = ResponseCache()

    private var storage: [String: CacheEntry] = [:]

    func get(_ url: String) -> CacheResponse? {
        guard let entry = storage[url] else { return nil }
        if entry.maxAge >= 0 {
            let age: TimeInterval = Date().timeIntervalSince(entry.timestamp)
            if age > Double(entry.maxAge) {
                storage.removeValue(forKey: url)
                return nil
            }
        }

        return entry.response
    }

    func set(_ url: String, response: CacheResponse, maxAge: Int) {
        storage[url] = CacheEntry(response, maxAge: maxAge)
    }
}
