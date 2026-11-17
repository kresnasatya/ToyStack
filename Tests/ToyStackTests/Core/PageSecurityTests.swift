import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct PageSecurityTests {
    @Test func plainHTTPPageIsNotSecure() async throws {
        let server: LocalPageServer = try LocalPageServer(reply: .page("<p>plain</p>"))
        defer { server.stop() }
        let (_, tab): (Browser, BrowserTab) = try Self.open(try await server.start())

        #expect(await Self.pump({ tab.isLoaded }))
        #expect(tab.isNotSecure)
        #expect(!tab.isSecure)
    }

    @Test func localFileIsNeitherSecureNorNotSecure() async throws {
        let path: String = NSTemporaryDirectory() + "security-\(UUID().uuidString).html"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "<p>local</p>".write(toFile: path, atomically: true, encoding: .utf8)
        let (_, tab): (Browser, BrowserTab) = try Self.open("file://" + path)

        #expect(await Self.pump({ tab.isLoaded }))
        #expect(!tab.isSecure)
        #expect(!tab.isNotSecure)
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
