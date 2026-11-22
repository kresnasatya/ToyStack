import Foundation
import Testing

@testable import Engine

/// The cookie jar is one store shared by every suite, so these tests run one
/// at a time and each uses a cookie value no other test sends. Both hosts are
/// IP literals so no HSTS rule set by another suite can send a hop over
/// https (RFC 6797 §8.1 never remembers an IP).
@Suite(.serialized)
struct RedirectCookieTests {
    @Test func cookieFromARedirectedPageBelongsToTheHostThatAnswered() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let port: Int = WebURL(try await server.start()).port
        let cookie: String = Self.uniqueCookie()
        server.setReply(.canonicalHost("127.0.0.1:\(port)", page: "<p>canonical</p>", cookie: cookie))

        _ = try await WebURL("http://[::1]:\(port)/page").request(bypassingCache: true)

        #expect(await CookieJar.shared.get("127.0.0.1")?.0 == cookie)
        #expect(await CookieJar.shared.get("[::1]")?.0 != cookie)
    }

    @Test func cookieSetOnARedirectIsSentToTheNextHop() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let port: Int = WebURL(try await server.start()).port
        let cookie: String = Self.uniqueCookie()
        server.setReply(.signIn(cookie: cookie, page: "<p>signed in</p>"))

        let response: (url: WebURL, status: Int, headers: [String: String], content: String) =
            try await WebURL("http://[::1]:\(port)/page").request(bypassingCache: true)

        #expect(response.content == "<p>signed in</p>")
        #expect(server.cookies.last == cookie)
        #expect(await CookieJar.shared.get("[::1]")?.0 == cookie)
    }

    @Test func redirectToAnotherHostDoesNotCarryTheFirstHostsCookie() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let port: Int = WebURL(try await server.start()).port
        let cookie: String = Self.uniqueCookie()
        await CookieJar.shared.set("[::1]", cookie: cookie, params: [:])
        server.setReply(.canonicalHost("127.0.0.1:\(port)", page: "<p>canonical</p>"))

        _ = try await WebURL("http://[::1]:\(port)/page").request(bypassingCache: true)

        #expect(server.cookies.count == 2)
        #expect(server.cookies.first == cookie)
        #expect(server.cookies.last != cookie)
    }

    private static func uniqueCookie() -> String {
        "session=\(UUID().uuidString)"
    }
}
