import CoreGraphics
import Foundation
import Testing

@testable import Engine

/// The local server speaks no TLS, so every https attempt against it fails
/// the way a real http-only site does. The shared host memories are cleared
/// before each test, and the tests run one at a time.
@Suite(.serialized)
@MainActor
struct HTTPFallbackNavigationTests {
    @Test func failedHTTPSGuessLoadsThePageOverHTTP() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain site</p>"))
        defer { server.stop() }
        let (_, tab, port): (Browser, BrowserTab, Int) = try await Self.open(server)
        await HTTPOnlyHosts.shared.forget("127.0.0.1")

        tab.open(Self.guess("127.0.0.1", port: port))

        #expect(await Self.pump({ Self.pageText(tab).contains("plain site") }))
        #expect(tab.url?.toString() == "http://127.0.0.1:\(port)/page")
        #expect(!tab.isSecure)
        #expect(server.secureAttempts >= 1)
        await HTTPOnlyHosts.shared.forget("127.0.0.1")
    }

    @Test func reloadAfterAFallbackGoesStraightToHTTP() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>first</p>"))
        defer { server.stop() }
        let (_, tab, port): (Browser, BrowserTab, Int) = try await Self.open(server)
        await HTTPOnlyHosts.shared.forget("127.0.0.1")
        tab.open(Self.guess("127.0.0.1", port: port))
        #expect(await Self.pump({ Self.pageText(tab).contains("first") }))
        await HTTPOnlyHosts.shared.forget("127.0.0.1")
        let attemptsBeforeReload: Int = server.secureAttempts

        server.setReply(.page("<p>second</p>"))
        tab.reload()

        #expect(await Self.pump({ Self.pageText(tab).contains("second") }))
        #expect(server.secureAttempts == attemptsBeforeReload)
    }

    @Test func hostThatFellBackBeforeSkipsHTTPSNextTime() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain site</p>"))
        defer { server.stop() }
        let (browser, tab, port): (Browser, BrowserTab, Int) = try await Self.open(server)
        await HTTPOnlyHosts.shared.forget("127.0.0.1")
        tab.open(Self.guess("127.0.0.1", port: port))
        #expect(await Self.pump({ Self.pageText(tab).contains("plain site") }))
        let attemptsBeforeSecondVisit: Int = server.secureAttempts
        tab.load(WebURL("about:blank"))
        #expect(await Self.pump({ !Self.pageText(tab).contains("plain site") }))

        tab.open(Self.guess("127.0.0.1", port: port))

        #expect(await Self.pump({ Self.pageText(tab).contains("plain site") }))
        await Self.finishQueuedFetches(browser)
        #expect(server.secureAttempts == attemptsBeforeSecondVisit)
        #expect(tab.url?.toString() == "http://127.0.0.1:\(port)/page")
        await HTTPOnlyHosts.shared.forget("127.0.0.1")
    }

    @Test func httpsOnlySiteNeverFallsBack() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain site</p>"))
        defer { server.stop() }
        let (browser, tab, port): (Browser, BrowserTab, Int) = try await Self.open(server)
        await HTTPOnlyHosts.shared.forget("localhost")
        await HSTSStore.shared.note("max-age=600", from: WebURL("https://localhost/"))

        tab.open(Self.guess("localhost", port: port))
        #expect(await Self.pump({ server.secureAttempts >= 1 }))
        await Self.finishQueuedFetches(browser)
        await HSTSStore.shared.note("max-age=0", from: WebURL("https://localhost/"))

        #expect(server.requests.isEmpty)
        #expect(tab.url?.toString() == "about:blank")
    }

    @Test func typedHTTPSAddressNeverFallsBack() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain site</p>"))
        defer { server.stop() }
        let (browser, tab, port): (Browser, BrowserTab, Int) = try await Self.open(server)

        tab.load(WebURL("https://127.0.0.1:\(port)/page"))
        #expect(await Self.pump({ server.secureAttempts >= 1 }))
        await Self.finishQueuedFetches(browser)

        #expect(server.requests.isEmpty)
        #expect(tab.url?.toString() == "about:blank")
    }

    // MARK: - Helpers

    private static func guess(_ host: String, port: Int) -> TypedAddress {
        TypedAddress(
            url: WebURL("https://\(host):\(port)/page"),
            fallback: WebURL("http://\(host):\(port)/page")
        )
    }

    private static func open(_ server: LocalPageServer) async throws -> (Browser, BrowserTab, Int) {
        let port: Int = WebURL(try await server.start()).port
        let browser: Browser = Browser()
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("about:blank"))
        browser.pauseAnimationTimer()
        return (browser, try #require(browser.activeTab), port)
    }

    private static func pageText(_ tab: BrowserTab) -> String {
        treeToList(tab.rootFrame.nodes).compactMap({ $0.text }).map(\.text).joined()
    }

    /// Fetches run one at a time in order, so an empty fetch queued now
    /// completes only after every fetch already queued has finished.
    private static func finishQueuedFetches(_ browser: Browser) async {
        await browser.networkTaskRunner.schedule(name: "finish-queued-fetches", { @Sendable () async -> Void in })
    }

    private static func pump(_ condition: () -> Bool) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }
}
