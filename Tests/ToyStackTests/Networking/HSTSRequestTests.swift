import Foundation
import Testing

@testable import Engine

/// The shared store is changed for "localhost" only, and these tests run one
/// at a time so they never see each other's rule.
@Suite(.serialized)
struct HSTSRequestTests {
    @Test func plainRequestToAnHTTPSOnlyHostIsSentOverHTTPS() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain</p>"))
        defer { server.stop() }
        let port: Int = try await Self.port(of: server)
        await Self.markLocalhostHTTPSOnly()

        _ = try? await WebURL("http://localhost:\(port)/style.css").request()
        await Self.forgetLocalhost()

        #expect(server.requests.isEmpty)
        #expect(server.secureAttempts >= 1)
    }

    @Test func imageRequestToAnHTTPSOnlyHostIsSentOverHTTPS() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("not an image"))
        defer { server.stop() }
        let port: Int = try await Self.port(of: server)
        await Self.markLocalhostHTTPSOnly()

        _ = try? await WebURL("http://localhost:\(port)/cat.png").requestRawBytes()
        await Self.forgetLocalhost()

        #expect(server.requests.isEmpty)
        #expect(server.secureAttempts >= 1)
    }

    @Test func redirectToAnHTTPSOnlyHostIsFollowedOverHTTPS() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let port: Int = try await Self.port(of: server)
        server.setReply(.redirect("http://localhost:\(port)/next"))
        await Self.markLocalhostHTTPSOnly()

        _ = try? await WebURL("http://127.0.0.1:\(port)/page").request(bypassingCache: true)
        await Self.forgetLocalhost()

        #expect(server.requests.count == 1)
        #expect(server.secureAttempts >= 1)
    }

    @Test func hostWithoutARuleStaysOnHTTP() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain</p>"))
        defer { server.stop() }
        let port: Int = try await Self.port(of: server)
        await Self.forgetLocalhost()

        let (_, _, body): (Int, [String: String], String) =
            try await WebURL("http://localhost:\(port)/page").request(bypassingCache: true)

        #expect(body == "<p>plain</p>")
        #expect(server.secureAttempts == 0)
    }

    private static func port(of server: LocalPageServer) async throws -> Int {
        WebURL(try await server.start()).port
    }

    private static func markLocalhostHTTPSOnly() async {
        await HSTSStore.shared.note("max-age=600", from: WebURL("https://localhost/"))
    }

    private static func forgetLocalhost() async {
        await HSTSStore.shared.note("max-age=0", from: WebURL("https://localhost/"))
    }
}
