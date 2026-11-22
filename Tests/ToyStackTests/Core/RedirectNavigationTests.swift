import CoreGraphics
import Foundation
import Testing

@testable import Engine

/// Both addresses are IP literals so no HSTS rule set by another suite can
/// send the redirect over https (RFC 6797 §8.1 never remembers an IP).
@Suite(.serialized)
@MainActor
struct RedirectNavigationTests {
    @Test func pageTakesTheAddressTheRedirectEndedAt() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let (_, tab, port): (Browser, BrowserTab, Int) = try await Self.open(server)
        server.setReply(.canonicalHost("127.0.0.1:\(port)", page: "<p>canonical</p>"))

        tab.load(WebURL("http://[::1]:\(port)/page"))

        #expect(await Self.pump({ Self.pageText(tab).contains("canonical") }))
        #expect(tab.url?.toString() == "http://127.0.0.1:\(port)/page")
    }

    @Test func reloadAsksTheAddressTheRedirectEndedAt() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page(""))
        defer { server.stop() }
        let (browser, tab, port): (Browser, BrowserTab, Int) = try await Self.open(server)
        server.setReply(.canonicalHost("127.0.0.1:\(port)", page: "<p>canonical</p>"))
        tab.load(WebURL("http://[::1]:\(port)/page"))
        #expect(await Self.pump({ Self.pageText(tab).contains("canonical") }))
        let requestsBeforeReload: Int = server.requests.count

        tab.reload()

        #expect(await Self.pump({ server.requests.count > requestsBeforeReload }))
        await Self.finishQueuedFetches(browser)
        #expect(server.requests.count == requestsBeforeReload + 1)
    }

    // MARK: - Helpers

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
