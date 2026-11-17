import Foundation

/// URLSession follows redirects on its own, so the HSTS rewrite also has to
/// happen here or a redirect to http:// would leave the browser unencrypted.
final class HSTSRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared: HSTSRedirect = HSTSRedirect()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let target: URL = request.url else { return request }
        let upgraded: WebURL = await HSTSStore.shared.upgrade(WebURL(target.absoluteString))
        guard upgraded.scheme != target.scheme, let upgradedURL: URL = URL(string: upgraded.toString()) else {
            return request
        }
        var secureRequest: URLRequest = request
        secureRequest.url = upgradedURL
        return secureRequest
    }
}
