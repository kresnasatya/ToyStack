import Foundation

final class RedirectFollower: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared: RedirectFollower = RedirectFollower()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let target: URL = request.url else { return request }
        await RememberedHeaders.record(from: response)

        var nextRequest: URLRequest = request
        let next: WebURL = await HSTSStore.shared.upgrade(WebURL(target.absoluteString))
        if next.scheme != target.scheme, let upgradedURL: URL = URL(string: next.toString()) {
            nextRequest.url = upgradedURL
        }
        let referrerHost: String? = request.value(forHTTPHeaderField: "Referer").map({ (referrer: String) -> String in WebURL(referrer).host })
        let cookie: String? = await CookieJar.shared.header(
            for: next, method: request.httpMethod ?? "GET", referrerHost: referrerHost
        )
        nextRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        return nextRequest
    }
}
