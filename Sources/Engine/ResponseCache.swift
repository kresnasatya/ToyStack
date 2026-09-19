import Foundation

struct HttpResponse {
    let status: Int
    let headers: [String: String]
    let content: String
}

// MARK: - CacheEntry

struct CacheEntry {
    let response: HttpResponse
    let timestamp: Date
    let maxAge: Int

    init(_ response: HttpResponse, maxAge: Int, now: Date = Date()) {
        self.response = response
        self.timestamp = now
        self.maxAge = maxAge
    }
}

// MARK: - ResponseCache

actor ResponseCache {
    static let shared: ResponseCache = ResponseCache()

    private var storage: [String: CacheEntry] = [:]

    func get(_ url: String) -> HttpResponse? {
        guard let entry = storage[url] else { return nil }
        if entry.maxAge >= 0 {
            let age = Date().timeIntervalSince(entry.timestamp)
            if age > Double(entry.maxAge) {
                storage.removeValue(forKey: url)
                return nil
            }
        }

        return HttpResponse(
            status: entry.response.status,
            headers: entry.response.headers,
            content: entry.response.content
        )
    }

    func set(_ url: String, response: HttpResponse, maxAge: Int) {
        storage[url] = CacheEntry(
            HttpResponse(status: response.status, headers: response.headers, content: response.content),
            maxAge: maxAge
        )
    }
}
