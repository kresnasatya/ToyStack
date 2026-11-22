import Foundation
import Testing

@testable import Engine

/// The local test server speaks no TLS, and an HSTS header only counts over
/// https (RFC 6797 §8.1), so these tests hand a redirect straight to the
/// follower instead of going through a server. Each test owns its host and
/// forgets its rule at the end.
@Suite struct RedirectFollowerTests {
    @Test func hstsRuleOnARedirectIsRemembered() async throws {
        let host: String = "hsts-redirect.test"

        _ = await Self.follow(
            from: "https://\(host)/", to: "https://www.\(host)/", headers: ["Strict-Transport-Security": "max-age=600"]
        )
        let remembered: Bool = await HSTSStore.shared.isKnown(host)
        await Self.forget(host)

        #expect(remembered)
    }

    @Test func redirectToHTTPOnTheHostThatJustSentHSTSGoesOverHTTPS() async throws {
        let host: String = "hsts-redirect-downgrade.test"

        let next: URLRequest? = await Self.follow(
            from: "https://\(host)/", to: "http://\(host)/next", headers: ["Strict-Transport-Security": "max-age=600"]
        )
        await Self.forget(host)

        #expect(next?.url?.absoluteString == "https://\(host)/next")
    }

    @Test func hstsRuleOnAPlainHTTPRedirectIsIgnored() async throws {
        let host: String = "hsts-redirect-plain.test"

        _ = await Self.follow(
            from: "http://\(host)/", to: "http://www.\(host)/", headers: ["Strict-Transport-Security": "max-age=600"]
        )
        let remembered: Bool = await HSTSStore.shared.isKnown(host)
        await Self.forget(host)

        #expect(!remembered)
    }

    private static func follow(from source: String, to target: String, headers: [String: String]) async -> URLRequest? {
        let sourceURL: URL = URL(string: source)!
        var redirectHeaders: [String: String] = headers
        redirectHeaders["Location"] = target
        let response: HTTPURLResponse = HTTPURLResponse(
            url: sourceURL, statusCode: 308, httpVersion: "HTTP/1.1", headerFields: redirectHeaders
        )!
        let task: URLSessionTask = URLSession.shared.dataTask(with: sourceURL)
        return await RedirectFollower.shared.urlSession(
            URLSession.shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: target)!)
        )
    }

    private static func forget(_ host: String) async {
        await HSTSStore.shared.note("max-age=0", from: WebURL("https://\(host)/"))
    }
}
