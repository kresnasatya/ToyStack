import Foundation

// MARK: - CookieJar
//
// An "actor" is a special Swift type (introduced in Swift 5.5 / macOS 12+)
// designed for safe access in concurrent (async) environments.
//
// The problem with a plain global variable like:
//    var COOKIE_JAR: [String: ...] = [:]
// ...is that when multiple async tasks run at the same time, they could
// read and write to it simultaneously, corrupting the data. This is called
// a "data race".
//
// An actor solves this by ensuring only ONE task can access it's internal
// data at a time. Swift enforces this at compile time - you MUST use
// "await" when calling actor methods, which signals that your code may
// pause and wait for the actor to become available.
//
// "static let shared" is the Singleton pattern - it means where there is only
// ever ONE instance of CookieJar throughout the entire app, shared globally.
// This replaces the old global variable COOKIE_JAR.
actor CookieJar {
    // "static" means this belongs to the type itself, not to any instance.
    // "let" means it can never be reassigned after creation.
    // So CookieJar.shared is created once and reused everywhere.
    static let shared = CookieJar()

    // "private" means only code inside this actor can touch this variable directly.
    // Outside code must go through get() and set() method below.
    private var storage: [String: (String, [String: String])] = [:]

    // Returns the cookie and it's params for a given host, or nil if not found.
    // Since this is an actor method, callers must use "await" to call it.
    func get(_ host: String) -> (String, [String: String])? {
        return storage[host]
    }

    // Stores a cookie and it's params for a given host.
    // Again, callers must use "await" - the actor serializes all writes,
    // so no two tasks can write at the same time.
    func set(_ host: String, cookie: String, params: [String: String]) {
        storage[host] = (cookie, params)
    }
}

// MARK: - WebURL

public class WebURL: @unchecked Sendable {

    // The URL scheme (http or https)
    let scheme: String

    // The host name (e.g., "example.com")
    var host: String

    // The port number (80 for http, 443 for https by default)
    let port: Int

    // The path component (e.g., "/path/to/resource")
    let path: String

    let mimeType: String

    // Parses a raw URL string like "https://example.com/path"
    // into it's individual components: scheme, host, port, and path.
    public init(_ rawURL: String) {
        if rawURL.hasPrefix("data:") {
            scheme = "data"
            host = ""
            port = 0
            let afterScheme = String(rawURL.dropFirst(5))  // remove "data:"
            if let commaIdx = afterScheme.firstIndex(of: ",") {
                mimeType = String(afterScheme[afterScheme.startIndex..<commaIdx])
                path = String(afterScheme[afterScheme.index(after: commaIdx)...])
            } else {
                mimeType = ""
                path = ""
            }
            return
        }

        if rawURL.hasPrefix("view-source:") {
            scheme = "view-source"
            host = ""
            port = 0
            mimeType = ""
            path = String(rawURL.dropFirst(12))  // remove "view-source:"
            return
        }

        guard let schemeRange = rawURL.range(of: "://") else {
            fatalError("Invalid URL: missing scheme")
        }
        scheme = String(rawURL[rawURL.startIndex..<schemeRange.lowerBound])
        assert(
            scheme == "http" || scheme == "https" || scheme == "file",
            "Unsupported scheme: \(scheme)")

        var rest = String(rawURL[schemeRange.upperBound...])
        if !rest.contains("/") {
            // If there's no path, add a trailing slash to represent root "/"
            rest += "/"
        }

        let slashIdx = rest.firstIndex(of: "/")!
        var hostPart = String(rest[rest.startIndex..<slashIdx])
        let pathPart = String(rest[slashIdx...])
        path = pathPart.isEmpty ? "/" : pathPart

        var defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : 0)
        if hostPart.contains(":") {
            // A custom part was provided, e.g. "example.com:8080"
            let parts = hostPart.split(separator: ":", maxSplits: 1)
            hostPart = String(parts[0])
            defaultPort = Int(parts[1])!
        }
        host = hostPart
        port = defaultPort
        mimeType = ""
    }

    // "async" means this function can be suspended while waiting for the
    // network response, allowing other tasks to run in the meantime.
    // "throws" means this function can fail and propagate errors to the caller,
    // who must handle them with "try".
    func request(
        referrer: WebURL? = nil, payload: String? = nil, extraHeaders: [String: String] = [:]
    ) async throws -> (
        headers: [String: String], content: String
    ) {
        if scheme == "file" {
            // Read the file at `path` and return its contents
            let content = try String(contentsOfFile: path, encoding: .utf8)
            return (headers: [:], content: content)
        }

        if scheme == "data" {
            return (headers: [:], content: path)
        }

        if scheme == "view-source" {
            let innerURL = WebURL(path)
            let (_, content) = try await innerURL.request()
            let escaped =
                content
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return (headers: [:], content: escaped)
        }

        // If a payload (body) is provided, use POST. Otherwise GET.
        let method = payload != nil ? "POST" : "GET"

        // URLComponents is a Foundation type that safely builds a URL
        // from its individual parts (scheme, host, port, path)
        var components = Foundation.URLComponents()
        components.scheme = scheme
        components.host = host
        components.port =
            (scheme == "https" && port == 443) || (scheme == "http" && port == 80) ? nil : port
        components.path = path

        guard let foundationURL = components.url else {
            fatalError("Could not construct URL from components")
        }

        var urlRequest = URLRequest(url: foundationURL)
        urlRequest.httpMethod = method
        urlRequest.setValue(host, forHTTPHeaderField: "Host")
        urlRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")
        urlRequest.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        for (key, value) in extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Check if we have a stored cookie for this host.
        // "await" is required here because CookieJar is an actor -
        // we must wait for it to be available before reading from it.
        if let (cookie, params) = await CookieJar.shared.get(host) {
            var allowCookie = true
            // SameSite=Lax means: don't sent the cookie on cross-site
            // non-GET requests (e.g. a POST form from another domain)
            if let ref = referrer, params["samesite"] == "lax" {
                if method != "GET" {
                    allowCookie = host == ref.host
                }
            }
            if allowCookie {
                urlRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
        }

        if let body = payload {
            // Encode the body as UTF-8 bytes and attach it to the request.
            urlRequest.httpBody = body.data(using: .utf8)
            // Content-Length tells the server how many bytes to expect.
            urlRequest.setValue("\(body.utf8.count)", forHTTPHeaderField: "Content-Length")
        }

        // "try await" means: this can both fail (throws) and suspend (async).
        // Swift pauses here until the full response is received, then resumes.
        // No semaphore or callback needed - the compiler handles the suspension
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        // "as?" is a conditional cast - it tries to cast "response" to
        // HTTPURLResponse. If it fails, the guard triggers fatalError.
        guard let httpResponse = response as? HTTPURLResponse else {
            fatalError("Invalid response type")
        }

        // print("version: HTTP/1.1")
        // print("status: ", httpResponse.statusCode)
        // print(
        //     "explaination: ",
        //     HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))

        // allHeaderFields is a dictionary of response headers from the server.
        // We lowercase all keys for consistent, case-insensitive lookups later.
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }

        // If the server sent a Set-Cookie header, parse, and store it
        if let setCookie = headers["set-cookie"] {
            var cookieStr = setCookie
            var cookieParams: [String: String] = [:]
            if cookieStr.contains(";") {
                // Cookie format: "name=value; SameSite=Lax; HttpOnly"
                // Split off the actual cookie value from its attributes.
                let parts = cookieStr.split(separator: ";", maxSplits: 1)
                cookieStr = String(parts[0])
                if parts.count > 1 {
                    let rest = String(parts[1])
                    for param in rest.split(separator: ";") {
                        let trimmed = param.trimmingCharacters(in: .whitespaces)
                        if trimmed.contains("=") {
                            let kv = trimmed.split(separator: "=", maxSplits: 1)
                            cookieParams[String(kv[0]).lowercased()] = String(kv[1]).lowercased()
                        } else {
                            // Attributes like "HttpOnly" have no value, so we store "true"
                            cookieParams[trimmed.lowercased()] = "true"
                        }
                    }
                }
            }

            // "await" is required because CookieJar is an actor
            // The actor ensures this write won't conflict the concurrent reads/writes.
            await CookieJar.shared.set(self.host, cookie: cookieStr, params: cookieParams)
        }

        let content = String(data: data, encoding: .utf8) ?? ""
        return (headers, content)
    }

    // Synchronous wrapper around request() for use in JavaScriptCore @convention(block) callbacks
    // JS callbacks must return immediately, so we block the current thread with a DispatchSemaphore
    // until the async request completes.
    func requestSync(payload: String? = nil) -> (headers: [String: String], content: String)? {
        final class ResultBox: @unchecked Sendable {
            var value: (headers: [String: String], content: String)?
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = try? await self.request(payload: payload)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    // Returns the URL as a string, omitting the port if it's the default.
    func toString() -> String {
        var portPart = ":\(port)"
        if scheme == "https" && port == 443 { portPart = "" }
        if scheme == "http" && port == 80 { portPart = "" }
        if scheme == "file" { portPart = "" }
        if scheme == "data" {
            return "data:\(mimeType),\(path)"
        }
        if scheme == "view-source" {
            return "view-source:\(path)"
        }
        return "\(scheme)://\(host)\(portPart)\(path)"
    }

    // Resolve a (possibly relative) URL againt this URL's base
    // e.g. if self is "https://example.com/a/b" and rawURL is "../c",
    // the result is "https://example.com/c"
    func resolve(_ rawURL: String) -> WebURL {
        // Absolute URL - use it directly
        if rawURL.contains("://") {
            return WebURL(rawURL)
        }

        // Protocol-relative URL like "//example.com/path" - inherit the scheme
        if rawURL.hasPrefix("//") {
            return WebURL("\(scheme):\(rawURL)")
        }
        // Absolute path - inherit scheme, host, and port
        if rawURL.hasPrefix("/") {
            return WebURL("\(scheme)://\(host):\(port)\(rawURL)")
        }

        // Relative path - resolve against the current path's directory
        var dir: String
        if let lastSlash = path.lastIndex(of: "/") {
            dir = String(path[path.startIndex..<lastSlash])
        } else {
            dir = ""
        }

        var relURL = rawURL
        // Each "../" moves one directory level up
        while relURL.hasPrefix("../") {
            relURL = String(relURL.dropFirst(3))
            if let lastSlash = dir.lastIndex(of: "/") {
                dir = String(dir[dir.startIndex..<lastSlash])
            }
        }

        return WebURL("\(scheme)://\(host):\(port)\(dir)/\(relURL)")
    }

    // Returns just the origin (scheme + host + port), used for
    // security checks like Same-Origin Policy.
    func origin() -> String {
        return "\(scheme)://\(host):\(port)"
    }
}
