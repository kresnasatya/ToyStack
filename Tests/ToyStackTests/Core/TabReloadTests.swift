import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct TabReloadTests {

    @Test func reloadShowsTheLatestVersionOfAFilePage() async throws {
        let path: String = NSTemporaryDirectory() + "reload-\(UUID().uuidString).html"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "<p>first version</p>".write(toFile: path, atomically: true, encoding: .utf8)
        let (browser, tab): (Browser, BrowserTab) = try Self.open("file://" + path)
        #expect(await Self.pump({ Self.pageText(tab).contains("first version") }))

        try "<p>second version</p>".write(toFile: path, atomically: true, encoding: .utf8)
        tab.reload()

        #expect(await Self.pump({ Self.pageText(tab).contains("second version") }))
        #expect(browser.activeTab === tab)
    }

    @Test func reloadAsksTheServerAgainInsteadOfShowingTheCachedCopy() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>first version</p>"))
        defer { server.stop() }
        let (_, tab): (Browser, BrowserTab) = try Self.open(try await server.start())
        #expect(await Self.pump({ Self.pageText(tab).contains("first version") }))

        server.setReply(.page("<p>second version</p>"))
        tab.reload()

        #expect(await Self.pump({ Self.pageText(tab).contains("second version") }))
        #expect(server.requests.count == 2)
    }

    @Test func reloadingAPageSourceShowsTheLatestSourceInsteadOfTheCachedCopy() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>first version</p>"))
        defer { server.stop() }
        let address: String = try await server.start()
        let (_, tab): (Browser, BrowserTab) = try Self.open("view-source:" + address)
        #expect(await Self.pump({ Self.pageText(tab).contains("first version") }))

        server.setReply(.page("<p>second version</p>"))
        tab.reload()

        #expect(await Self.pump({ Self.pageText(tab).contains("second version") }))
    }

    @Test func reloadDoesNotAddABackStep() async throws {
        let path: String = NSTemporaryDirectory() + "reload-\(UUID().uuidString).html"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "<p>page</p>".write(toFile: path, atomically: true, encoding: .utf8)
        let (_, tab): (Browser, BrowserTab) = try Self.open("file://" + path)
        #expect(await Self.pump({ tab.isLoaded }))

        tab.reload()
        tab.reload()

        #expect(!tab.canGoBack)
        #expect(!tab.canGoForward)
    }

    @Test func reloadRetriesAPageThatFailedToLoad() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .hangUp)
        defer { server.stop() }
        let (browser, tab): (Browser, BrowserTab) = try Self.open(try await server.start())
        #expect(await Self.pump({ !server.requests.isEmpty }))
        await Self.finishQueuedFetches(browser)
        #expect(tab.url == nil)

        server.setReply(.page("<p>back online</p>"))
        tab.reload()

        #expect(await Self.pump({ Self.pageText(tab).contains("back online") }))
    }

    @Test func reloadingAFormResultSendsTheFormAgainWhenConfirmed() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>thanks</p>"))
        defer { server.stop() }
        let address: String = try await server.start()
        let (_, tab): (Browser, BrowserTab) = try Self.open("about:blank")
        tab.load(WebURL(address), payload: "q=1")
        #expect(await Self.pump({ Self.pageText(tab).contains("thanks") }))
        var prompts: [String] = []
        let original: (String, String) -> Bool = BrowserTab.showConfirm
        BrowserTab.showConfirm = { (title: String, _: String) -> Bool in
            prompts.append(title)
            return true
        }
        defer { BrowserTab.showConfirm = original }

        tab.reload()

        #expect(await Self.pump({ server.requests.count == 2 }))
        #expect(server.requests.last == LocalPageServer.Request(method: "POST", body: "q=1"))
        #expect(prompts == ["Resubmit form?"])
    }

    @Test func reloadingAFormResultSendsNothingWhenDeclined() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>thanks</p>"))
        defer { server.stop() }
        let address: String = try await server.start()
        let (browser, tab): (Browser, BrowserTab) = try Self.open("about:blank")
        tab.load(WebURL(address), payload: "q=1")
        #expect(await Self.pump({ Self.pageText(tab).contains("thanks") }))
        let original: (String, String) -> Bool = BrowserTab.showConfirm
        BrowserTab.showConfirm = { (_: String, _: String) -> Bool in false }
        defer { BrowserTab.showConfirm = original }

        tab.reload()
        tab.load(WebURL(address))

        #expect(await Self.pump({ server.requests.contains(where: { $0.method == "GET" }) }))
        await Self.finishQueuedFetches(browser)
        #expect(server.requests.map(\.method) == ["POST", "GET"])
    }

    // MARK: - Helpers

    private static func open(_ address: String) throws -> (Browser, BrowserTab) {
        let browser: Browser = Browser()
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL(address))
        browser.pauseAnimationTimer()
        return (browser, try #require(browser.activeTab))
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
