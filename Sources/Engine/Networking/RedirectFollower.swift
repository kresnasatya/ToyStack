import Foundation

/// URLSession follows redirects on its own and copies every header we set to
/// the next hop. So each hop has to do here what the browser does for any
/// response: keep the redirect's HSTS rule and cookie, upgrade an HSTS host
/// to https, and send the next host only its own cookies.
final class RedirectFollower: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared: RedirectFollower = RedirectFollower()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let target: URL = request.url else { return request }
        // The redirect's own HSTS rule is noted first, so a redirect from
        // https to http on the same host is already upgraded below.
        await RememberedHeaders.record(from: response)

        var nextRequest: URLRequest = request
        let next: WebURL = await HSTSStore.shared.upgrade(WebURL(target.absoluteString))
        if next.scheme != target.scheme, let upgradedURL: URL = URL(string: next.toString()) {
            nextRequest.url = upgradedURL
        }
        let referrerHost: String? = request.value(forHTTPHeaderField: "Referer").map({ (referrer: String) -> String in WebURL(referrer).host })
        // `next` is the address after the HSTS upgrade, so a Secure cookie
        // goes along exactly when the hop really is https.
        let cookie: String? = await CookieJar.shared.header(
            for: next, method: request.httpMethod ?? "GET", referrerHost: referrerHost
        )
        nextRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        return nextRequest
    }
}
