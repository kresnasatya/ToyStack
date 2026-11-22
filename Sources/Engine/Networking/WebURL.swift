import Foundation

// MARK: - WebURL

public class WebURL: @unchecked Sendable {

    private static let dataPrefix: String = "data:"
    private static let viewSourcePrefix: String = "view-source:"
    private static let aboutPrefix: String = "about:"

    let scheme: String

    var host: String

    let port: Int

    let path: String

    let mimeType: String

    var fragment: String? = nil

    public init(_ rawURL: String) {
        if rawURL.hasPrefix(Self.dataPrefix) {
            scheme = "data"
            host = ""
            port = 0
            let afterScheme: String = String(rawURL.dropFirst(Self.dataPrefix.count))
            if let commaIdx = afterScheme.firstIndex(of: ",") {
                mimeType = String(afterScheme[afterScheme.startIndex..<commaIdx])
                path = String(afterScheme[afterScheme.index(after: commaIdx)...])
            } else {
                mimeType = ""
                path = ""
            }
            return
        }

        if rawURL.hasPrefix(Self.viewSourcePrefix) {
            scheme = "view-source"
            host = ""
            port = 0
            mimeType = ""
            path = String(rawURL.dropFirst(Self.viewSourcePrefix.count))
            return
        }

        if rawURL.hasPrefix(Self.aboutPrefix) {
            scheme = "about"
            host = ""
            port = 0
            path = String(rawURL.dropFirst(Self.aboutPrefix.count))
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

        let parsedScheme: String = String(rawURL[rawURL.startIndex..<schemeRange.lowerBound])
        guard parsedScheme == "http" || parsedScheme == "https" || parsedScheme == "file" else {
            scheme = "about"
            host = ""
            port = 0
            path = "blank"
            mimeType = ""
            return
        }
        scheme = parsedScheme

        var rest: String = String(rawURL[schemeRange.upperBound...])
        if !rest.contains("/") {
            rest += "/"
        }

        let slashIdx: String.Index = rest.firstIndex(of: "/")!
        var hostPart: String = String(rest[rest.startIndex..<slashIdx])
        let pathPart: String = String(rest[slashIdx...])
        if let hashIdx = pathPart.firstIndex(of: "#") {
            path = String(pathPart[pathPart.startIndex..<hashIdx])
            fragment = String(pathPart[pathPart.index(after: hashIdx)...])
        } else {
            path = pathPart.isEmpty ? "/" : pathPart
        }

        var defaultPort: Int = scheme == "https" ? 443 : (scheme == "http" ? 80 : 0)
        if hostPart.hasPrefix("["), let close: String.Index = hostPart.firstIndex(of: "]") {
            let afterHost: Substring = hostPart[hostPart.index(after: close)...]
            if afterHost.hasPrefix(":") {
                defaultPort = Int(afterHost.dropFirst()) ?? defaultPort
            }
            hostPart = String(hostPart[...close])
        } else if hostPart.contains(":") {
            let parts: [String.SubSequence] = hostPart.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            hostPart = String(parts[0])
            defaultPort = Int(parts[1]) ?? defaultPort
        }
        host = hostPart
        port = defaultPort
        mimeType = ""
    }

    func request(
        referrer: WebURL? = nil, payload: String? = nil, extraHeaders: [String: String] = [:], bypassingCache: Bool = false
    ) async throws -> (
        url: WebURL, status: Int, headers: [String: String], content: String
    ) {
        if let source = BrowserTab.pageSource, let page = await source(scheme, path) {
            return (url: self, status: page.status, headers: page.headers, content: page.content)
        }
        if scheme == "about" {
            return (url: self, status: 200, headers: [:], content: "")
        }

        if scheme == "file" {
            let content: String = try String(contentsOfFile: path, encoding: .utf8)
            return (url: self, status: 200, headers: [:], content: content)
        }

        if scheme == "data" {
            return (url: self, status: 200, headers: [:], content: path)
        }

        if scheme == "view-source" {
            let innerURL: WebURL = WebURL(path)
            let content: String = try await innerURL.request(bypassingCache: bypassingCache).content
            let highlighted: String = await MainActor.run {
                HTMLSyntaxHighlighter(body: content).highlight()
            }
            return (url: self, status: 200, headers: [:], content: highlighted)
        }

        let secureURL: WebURL = await HSTSStore.shared.upgrade(self)
        if secureURL !== self {
            return try await secureURL.request(
                referrer: referrer, payload: payload, extraHeaders: extraHeaders, bypassingCache: bypassingCache
            )
        }

        let method: String = payload != nil ? "POST" : "GET"

        let cacheKey: String = toString()
        if method == "GET" && !bypassingCache {
            if let cached = await ResponseCache.shared.get(cacheKey) {
                return (arrival(at: cached.redirectedTo), cached.status, cached.headers, cached.content)
            }
        }

        let urlRequest: URLRequest = await makeHTTPRequest(method: method, referrer: referrer, payload: payload, extraHeaders: extraHeaders)

        let (data, response) = try await URLSession.shared.data(for: urlRequest, delegate: HSTSRedirect.shared)
        let redirectedTo: String? = response.url.flatMap({ (final: URL) -> String? in
            final == urlRequest.url ? nil : final.absoluteString
        })

        guard let httpResponse = response as? HTTPURLResponse else {
            fatalError("Invalid response type")
        }

        let headers: [String: String] = await parseHeaders(httpResponse)

        let content: String = String(data: data, encoding: .utf8) ?? ""

        if method == "GET" && httpResponse.statusCode == 200 {
            let cacheControl: String = headers["cache-control"] ?? ""
            if cacheControl.contains("no-store") {

            } else if cacheControl.contains("max-age="),
                let range = cacheControl.range(of: "max-age="),
                let maxAge = Int(
                    cacheControl[range.upperBound...].prefix(while: { $0.isNumber })
                )
            {
                await ResponseCache.shared.set(
                    cacheKey,
                    response: CacheResponse(
                        status: httpResponse.statusCode,
                        headers: headers,
                        content: content,
                        redirectedTo: redirectedTo
                    ),
                    maxAge: maxAge
                )
            } else if cacheControl.isEmpty {
                await ResponseCache.shared.set(
                    cacheKey,
                    response: CacheResponse(
                        status: httpResponse.statusCode,
                        headers: headers,
                        content: content,
                        redirectedTo: redirectedTo
                    ),
                    maxAge: -1
                )
            }
        }

        return (arrival(at: redirectedTo), httpResponse.statusCode, headers, content)
    }

    /// Fetch §2.2.6 (location URL): a redirect target without a fragment
    /// takes the fragment of the request, so `/#about` still scrolls after a
    /// redirect to another host.
    private func arrival(at redirectedTo: String?) -> WebURL {
        guard let redirectedTo: String else { return self }
        let final: WebURL = WebURL(redirectedTo)
        if final.fragment == nil {
            final.fragment = fragment
        }
        return final
    }

    func makeHTTPRequest(method: String, referrer: WebURL?, payload: String?, extraHeaders: [String: String]) async -> URLRequest {
        var components: URLComponents = Foundation.URLComponents()
        components.scheme = scheme
        components.host = host
        components.port =
            (scheme == "https" && port == 443) || (scheme == "http" && port == 80) ? nil : port
        if let questionIdx = path.firstIndex(of: "?") {
            components.percentEncodedPath = PathPercentEncoding.encode(String(path[path.startIndex..<questionIdx]))
            components.percentEncodedQuery = String(path[path.index(after: questionIdx)...])
        } else {
            components.percentEncodedPath = PathPercentEncoding.encode(path)
        }

        guard let foundationURL = components.url else {
            fatalError("Could not construct URL from components")
        }

        var urlRequest: URLRequest = URLRequest(url: foundationURL)
        urlRequest.httpMethod = method
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
            var allowCookie: Bool = true
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

        return urlRequest
    }

    private func parseHeaders(_ httpResponse: HTTPURLResponse) async -> [String: String] {
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k.lowercased()] = v
            }
        }

        if let rule: String = headers["strict-transport-security"], let responseURL: URL = httpResponse.url {
            await HSTSStore.shared.note(rule, from: WebURL(responseURL.absoluteString))
        }

        if let setCookie = headers["set-cookie"] {
            var cookieStr: String = setCookie
            var cookieParams: [String: String] = [:]
            if cookieStr.contains(";") {
                let parts: [String.SubSequence] = cookieStr.split(separator: ";", maxSplits: 1)
                cookieStr = String(parts[0])
                if parts.count > 1 {
                    let rest: String = String(parts[1])
                    for param in rest.split(separator: ";") {
                        let trimmed: String = param.trimmingCharacters(in: .whitespaces)
                        if trimmed.contains("=") {
                            let kv: [String.SubSequence] = trimmed.split(separator: "=", maxSplits: 1)
                            cookieParams[String(kv[0]).lowercased()] = String(kv[1]).lowercased()
                        } else {
                            cookieParams[trimmed.lowercased()] = "true"
                        }
                    }
                }
            }

            await CookieJar.shared.set(self.host, cookie: cookieStr, params: cookieParams)
        }

        return headers
    }

    func requestRawBytes(referrer: WebURL? = nil) async throws -> (status: Int, headers: [String: String], data: Data) {
        if scheme == "file" {
            let data: Data = try Data(contentsOf: URL(fileURLWithPath: path))
            return (status: 200, headers: [:], data: data)
        }
        if scheme == "about" { return (status: 200, headers: [:], data: Data()) }
        if scheme == "data" {
            if mimeType.hasSuffix(";base64") {
                let type: String = String(mimeType.dropLast(";base64".count))
                return (status: 200, headers: ["content-type": type], data: Data(base64Encoded: path) ?? Data())
            }
            return (status: 200, headers: ["content-type": mimeType], data: Data(path.utf8))
        }

        let secureURL: WebURL = await HSTSStore.shared.upgrade(self)
        if secureURL !== self {
            return try await secureURL.requestRawBytes(referrer: referrer)
        }

        let urlRequest: URLRequest = await makeHTTPRequest(method: "GET", referrer: referrer, payload: nil, extraHeaders: [:])
        let (data, response) = try await URLSession.shared.data(for: urlRequest, delegate: HSTSRedirect.shared)
        guard let httpResponse = response as? HTTPURLResponse else {
            fatalError("Invalid response type")
        }
        let headers: [String: String] = await parseHeaders(httpResponse)
        return (httpResponse.statusCode, headers, data)
    }

    func requestSync(payload: String? = nil, extraHeaders: [String: String] = [:]) -> (
        url: WebURL, status: Int, headers: [String: String], content: String
    )? {
        final class ResultBox: @unchecked Sendable {
            var value: (url: WebURL, status: Int, headers: [String: String], content: String)?
        }
        let box: ResultBox = ResultBox()
        let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        Task {
            box.value = try? await self.request(payload: payload, extraHeaders: extraHeaders)
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    public func toString() -> String {
        var portPart: String = ":\(port)"
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

        var result: String = "\(scheme)://\(host)\(portPart)\(path)"
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

        var relURL: String = rawURL
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
