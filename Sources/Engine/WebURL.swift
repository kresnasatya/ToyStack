import Foundation

// MARK: - CookieJar

actor CookieJar {
    static let shared = CookieJar()

    private var storage: [String: (cookie: String, params: [String: String], expires: Date?)] = [:]

    func get(_ host: String) -> (String, [String: String])? {
        guard let entry = storage[host] else { return nil }
        if let expires = entry.expires, Date() > expires {
            storage.removeValue(forKey: host)
            return nil
        }
        return (entry.cookie, entry.params)
    }

    func set(_ host: String, cookie: String, params: [String: String]) {
        var expires: Date? = nil
        if let maxAge = params["max-age"], let seconds = Double(maxAge) {
            expires = Date().addingTimeInterval(seconds)
        } else if let expiresStr = params["expires"] {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            expires = formatter.date(from: expiresStr)
        }
        storage[host] = (cookie: cookie, params: params, expires: expires)
    }
}

// MARK: - CacheEntry

struct CacheEntry {
    let status: Int
    let headers: [String: String]
    let content: String
    let timestamp: Date
    let maxAge: Int
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
            status: status,
            headers: headers, content: content, timestamp: Date(), maxAge: maxAge)
    }
}

// MARK: - WebURL

public class WebURL: @unchecked Sendable {

    let scheme: String

    var host: String

    let port: Int

    let path: String

    let mimeType: String

    var fragment: String? = nil

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

        if rawURL.hasPrefix("about:") {
            scheme = "about"
            host = ""
            port = 0
            path = String(rawURL.dropFirst(6))  // "blank" from "about:blank"
            mimeType = ""
            return
        }

        guard let schemeRange = rawURL.range(of: "://") else {
            scheme = "about"
            host = ""
            port = 0
            path = "blank"
            mimeType = ""
            return
        }

        let parsedScheme = String(rawURL[rawURL.startIndex..<schemeRange.lowerBound])
        guard parsedScheme == "http" || parsedScheme == "https" || parsedScheme == "file" else {
            scheme = "about"
            host = ""
            port = 0
            path = "blank"
            mimeType = ""
            return
        }
        scheme = parsedScheme

        var rest = String(rawURL[schemeRange.upperBound...])
        if !rest.contains("/") {
            rest += "/"
        }

        let slashIdx = rest.firstIndex(of: "/")!
        var hostPart = String(rest[rest.startIndex..<slashIdx])
        let pathPart = String(rest[slashIdx...])
        if let hashIdx = pathPart.firstIndex(of: "#") {
            path = String(pathPart[pathPart.startIndex..<hashIdx])
            fragment = String(pathPart[pathPart.index(after: hashIdx)...])
        } else {
            path = pathPart.isEmpty ? "/" : pathPart
        }

        var defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : 0)
        if hostPart.contains(":") {
            let parts = hostPart.split(separator: ":", maxSplits: 1)
            hostPart = String(parts[0])
            defaultPort = Int(parts[1])!
        }
        host = hostPart
        port = defaultPort
        mimeType = ""
    }

    func request(
        referrer: WebURL? = nil, payload: String? = nil, extraHeaders: [String: String] = [:]
    ) async throws -> (
        status: Int, headers: [String: String], content: String
    ) {
        if scheme == "about" {
            if path == "bookmarks" {
                let items = bookmarks.map { url in
                    " <li><a href=\"\(url)\">\(url)</a></li>"
                }.joined(separator: "\n")
                let html = """
                    <html><body>
                    <h1>Bookmarks</h1>
                    <ul>\n\(items)\n</ul>
                    </body></html
                    """
                return (status: 200, headers: [:], content: html)
            }
            return (status: 200, headers: [:], content: "")
        }

        if scheme == "file" {
            // Read the file at `path` and return its contents
            let content = try String(contentsOfFile: path, encoding: .utf8)
            return (status: 200, headers: [:], content: content)
        }

        if scheme == "data" {
            return (status: 200, headers: [:], content: path)
        }

        if scheme == "view-source" {
            let innerURL = WebURL(path)
            let (_, _, content) = try await innerURL.request()
            return (status: 200, headers: [:], content: HTMLSyntaxHighlighter(body: content).highlight())
        }

        let method = payload != nil ? "POST" : "GET"

        let cacheKey = toString()
        if method == "GET" {
            if let cached = await ResponseCache.shared.get(cacheKey) {
                return cached
            }
        }

        var components = Foundation.URLComponents()
        components.scheme = scheme
        components.host = host
        components.port =
            (scheme == "https" && port == 443) || (scheme == "http" && port == 80) ? nil : port
        if let questionIdx = path.firstIndex(of: "?") {
            components.path = String(path[path.startIndex..<questionIdx])
            components.percentEncodedQuery = String(path[path.index(after: questionIdx)...])
        } else {
            components.path = path
        }

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
        urlRequest.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        for (key, value) in extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let ref = referrer {
            urlRequest.setValue(ref.toString(), forHTTPHeaderField: "Referer")
        }

        if let (cookie, params) = await CookieJar.shared.get(host) {
            var allowCookie = true
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
            urlRequest.httpBody = body.data(using: .utf8)
            urlRequest.setValue("\(body.utf8.count)", forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            fatalError("Invalid response type")
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }

        if let setCookie = headers["set-cookie"] {
            var cookieStr = setCookie
            var cookieParams: [String: String] = [:]
            if cookieStr.contains(";") {
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
                            cookieParams[trimmed.lowercased()] = "true"
                        }
                    }
                }
            }

            await CookieJar.shared.set(self.host, cookie: cookieStr, params: cookieParams)
        }

        let content = String(data: data, encoding: .utf8) ?? ""

        if method == "GET" && httpResponse.statusCode == 200 {
            let cacheControl = headers["cache-control"] ?? ""
            if cacheControl.contains("no-store") {

            } else if cacheControl.contains("max-age="),
                let range = cacheControl.range(of: "max-age="),
                let maxAge = Int(
                    cacheControl[range.upperBound...].prefix(while: { $0.isNumber })
                )
            {
                await ResponseCache.shared.set(
                    cacheKey, status: httpResponse.statusCode, headers: headers, content: content, maxAge: maxAge)
            } else if cacheControl.isEmpty {
                await ResponseCache.shared.set(
                    cacheKey, status: httpResponse.statusCode, headers: headers, content: content, maxAge: -1)
            }
        }

        return (httpResponse.statusCode, headers, content)
    }

    func requestSync(payload: String? = nil, extraHeaders: [String: String] = [:]) -> (
        status: Int, headers: [String: String], content: String
    )? {
        final class ResultBox: @unchecked Sendable {
            var value: (status: Int, headers: [String: String], content: String)?
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = try? await self.request(payload: payload, extraHeaders: extraHeaders)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

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
        if scheme == "about" {
            return "about:\(path)"
        }

        var result = "\(scheme)://\(host)\(portPart)\(path)"
        if let f = fragment { result += "#\(f)" }
        return result
    }

    func resolve(_ rawURL: String) -> WebURL {
        if rawURL.hasPrefix("#") {
            return WebURL("\(scheme)://\(host):\(port)\(path)\(rawURL)")
        }

        if rawURL.contains("://") {
            return WebURL(rawURL)
        }

        if rawURL.hasPrefix("//") {
            return WebURL("\(scheme):\(rawURL)")
        }

        if rawURL.hasPrefix("/") {
            return WebURL("\(scheme)://\(host):\(port)\(rawURL)")
        }

        var dir: String
        if let lastSlash = path.lastIndex(of: "/") {
            dir = String(path[path.startIndex..<lastSlash])
        } else {
            dir = ""
        }

        var relURL = rawURL
        while relURL.hasPrefix("../") {
            relURL = String(relURL.dropFirst(3))
            if let lastSlash = dir.lastIndex(of: "/") {
                dir = String(dir[dir.startIndex..<lastSlash])
            }
        }

        return WebURL("\(scheme)://\(host):\(port)\(dir)/\(relURL)")
    }

    func origin() -> String {
        return "\(scheme)://\(host):\(port)"
    }
}
