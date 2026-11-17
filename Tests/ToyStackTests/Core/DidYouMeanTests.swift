import CoreGraphics
import Foundation
import Testing

@testable import Engine

/// `BrowserTab.hostExists` is shared, so these tests run one at a time and
/// put the real lookup back when done.
@Suite(.serialized)
@MainActor
struct DidYouMeanTests {
    private static let intranet: WebURL = WebURL("http://intranet/")

    @Test func searchedWordThatIsAMachineOnTheNetworkOffersIt() async throws {
        let (_, tab): (Browser, BrowserTab) = try Self.open()
        let restore: (String) async -> Bool = Self.stubLookup({ (_: String) async -> Bool in true })
        defer { BrowserTab.hostExists = restore }

        tab.open(Self.searchForIntranet())

        #expect(await Self.pump({ tab.didYouMean != nil }))
        #expect(tab.didYouMean === Self.intranet)
    }

    @Test func searchedWordThatNoMachineHasOffersNothing() async throws {
        let (_, tab): (Browser, BrowserTab) = try Self.open()
        let asked: LookupLog = LookupLog()
        let restore: (String) async -> Bool = Self.stubLookup({ (host: String) async -> Bool in
            await asked.add(host)
            return false
        })
        defer { BrowserTab.hostExists = restore }

        tab.open(Self.searchForIntranet())

        #expect(await Self.pump({ await asked.hosts == ["intranet"] }))
        #expect(await !Self.pump({ tab.didYouMean != nil }, seconds: 0.2))
    }

    @Test func answerForAnEarlierNavigationIsIgnored() async throws {
        let (_, tab): (Browser, BrowserTab) = try Self.open()
        let gate: LookupGate = LookupGate()
        let restore: (String) async -> Bool = Self.stubLookup({ (_: String) async -> Bool in await gate.wait() })
        defer { BrowserTab.hostExists = restore }

        tab.open(Self.searchForIntranet())
        #expect(await Self.pump({ await gate.isWaiting }))
        tab.load(WebURL("about:blank"))
        await gate.open(answer: true)

        #expect(await !Self.pump({ tab.didYouMean != nil }, seconds: 0.2))
    }

    @Test func nextNavigationRemovesTheOffer() async throws {
        let (_, tab): (Browser, BrowserTab) = try Self.open()
        let restore: (String) async -> Bool = Self.stubLookup({ (_: String) async -> Bool in true })
        defer { BrowserTab.hostExists = restore }
        tab.open(Self.searchForIntranet())
        #expect(await Self.pump({ tab.didYouMean != nil }))

        tab.load(WebURL("about:blank"))

        #expect(tab.didYouMean == nil)
    }

    @Test func dismissedOfferIsGone() async throws {
        let (_, tab): (Browser, BrowserTab) = try Self.open()
        let restore: (String) async -> Bool = Self.stubLookup({ (_: String) async -> Bool in true })
        defer { BrowserTab.hostExists = restore }
        tab.open(Self.searchForIntranet())
        #expect(await Self.pump({ tab.didYouMean != nil }))

        tab.dismissDidYouMean()

        #expect(tab.didYouMean == nil)
    }

    @Test func addressWithoutAnAlternateNeverLooksUpAHost() async throws {
        let (_, tab): (Browser, BrowserTab) = try Self.open()
        let asked: LookupLog = LookupLog()
        let restore: (String) async -> Bool = Self.stubLookup({ (host: String) async -> Bool in
            await asked.add(host)
            return true
        })
        defer { BrowserTab.hostExists = restore }

        tab.open(TypedAddress(url: WebURL("about:blank")))

        #expect(await !Self.pump({ await !asked.hosts.isEmpty }, seconds: 0.2))
        #expect(tab.didYouMean == nil)
    }

    // MARK: - Helpers

    /// The search page itself is not fetched: about:blank stands in for it.
    private static func searchForIntranet() -> TypedAddress {
        TypedAddress(url: WebURL("about:blank"), alternate: intranet)
    }

    private static func stubLookup(_ stub: @escaping (String) async -> Bool) -> (String) async -> Bool {
        let original: (String) async -> Bool = BrowserTab.hostExists
        BrowserTab.hostExists = stub
        return original
    }

    private static func open() throws -> (Browser, BrowserTab) {
        let browser: Browser = Browser()
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("about:blank"))
        browser.pauseAnimationTimer()
        return (browser, try #require(browser.activeTab))
    }

    private static func pump(_ condition: () async -> Bool, seconds: TimeInterval = 10) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(seconds)
        while await !condition() {
            guard Date() < deadline else { return false }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return true
    }
}

// MARK: - Lookup doubles

private actor LookupLog {
    private(set) var hosts: [String] = []

    func add(_ host: String) {
        hosts.append(host)
    }
}

private actor LookupGate {
    private var waiter: CheckedContinuation<Bool, Never>? = nil

    var isWaiting: Bool { waiter != nil }

    func wait() async -> Bool {
        await withCheckedContinuation({ (continuation: CheckedContinuation<Bool, Never>) in
            waiter = continuation
        })
    }

    func open(answer: Bool) {
        waiter?.resume(returning: answer)
        waiter = nil
    }
}
