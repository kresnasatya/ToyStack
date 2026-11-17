import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct HSTSNavigationTests {
    @Test func plainAddressOfAnHTTPSOnlySiteOpensTheSecurePage() async throws {
        let host: String = "hsts-\(UUID().uuidString.lowercased()).example"
        await HSTSStore.shared.note("max-age=600", from: WebURL("https://\(host)/"))
        let path: String = "/\(UUID().uuidString)"

        try await PageSourceOverride.with({ (scheme: String, requested: String) in
            guard requested == path else { return nil }
            return (200, [:], "<p>\(scheme) page</p>")
        }) {
            let (_, tab): (Browser, BrowserTab) = try Self.open("http://\(host)\(path)")

            #expect(await Self.pump({ tab.isLoaded }))
            #expect(tab.url?.toString() == "https://\(host)\(path)")
            #expect(tab.isSecure)
            #expect(!tab.isNotSecure)
        }
        await HSTSStore.shared.note("max-age=0", from: WebURL("https://\(host)/"))
    }

    @Test func plainAddressOfAnOrdinarySiteStaysPlain() async throws {
        let host: String = "plain-\(UUID().uuidString.lowercased()).example"
        let path: String = "/\(UUID().uuidString)"

        try await PageSourceOverride.with({ (scheme: String, requested: String) in
            guard requested == path else { return nil }
            return (200, [:], "<p>\(scheme) page</p>")
        }) {
            let (_, tab): (Browser, BrowserTab) = try Self.open("http://\(host)\(path)")

            #expect(await Self.pump({ tab.isLoaded }))
            #expect(tab.url?.toString() == "http://\(host)\(path)")
            #expect(!tab.isSecure)
            #expect(tab.isNotSecure)
        }
    }

    private static func open(_ address: String) throws -> (Browser, BrowserTab) {
        let browser: Browser = Browser()
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL(address))
        browser.pauseAnimationTimer()
        return (browser, try #require(browser.activeTab))
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
