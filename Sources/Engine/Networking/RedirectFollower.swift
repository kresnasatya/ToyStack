import Foundation

/// URLSession follows redirects on its own and copies every header we set to
/// the next hop. So each hop has to do here what the browser does for any
/// response: keep the redirect's cookies, send the next host only its own
/// cookies, and upgrade an HSTS host to https.
final class RedirectFollower: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared: RedirectFollower = RedirectFollower()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let target: URL = request.url else { return request }
        if let setCookie: String = response.value(forHTTPHeaderField: "Set-Cookie"), let redirectedFrom: URL = response.url {
            await CookieJar.shared.receive(setCookie, from: WebURL(redirectedFrom.absoluteString).host)
        }

        var nextRequest: URLRequest = request
        let next: WebURL = await HSTSStore.shared.upgrade(WebURL(target.absoluteString))
        if next.scheme != target.scheme, let upgradedURL: URL = URL(string: next.toString()) {
            nextRequest.url = upgradedURL
        }
        let referrerHost: String? = request.value(forHTTPHeaderField: "Referer").map({ (referrer: String) -> String in WebURL(referrer).host })
        let cookie: String? = await CookieJar.shared.header(
            for: next.host, method: request.httpMethod ?? "GET", referrerHost: referrerHost
        )
        nextRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        return nextRequest
    }
}
