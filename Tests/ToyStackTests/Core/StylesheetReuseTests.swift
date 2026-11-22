import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StylesheetReuseTests {
    @Test func domChangeReusesTheStylesheetLoadedWithThePage() async throws {
        let site: FakeSite = FakeSite()
        site.reply("/main.css", with: "p { color: red; }")
        site.reply(site.pagePath, with: """
            <html><head><link rel="stylesheet" href="/main.css"></head>
            <body><div id="bars"></div>
            <script>document.getElementById('bars').innerHTML = '<p>up</p>';</script>
            </body></html>
            """)

        try await PageSourceOverride.with(site.source) {
            let tab: BrowserTab = try await Self.open(site)

            #expect(site.requests(for: "/main.css") == 1)
            #expect(Self.hasRule(tab, color: "red"))
        }
    }

    @Test func stylesheetInsertedByAScriptIsDownloadedOnce() async throws {
        let site: FakeSite = FakeSite()
        site.reply("/late.css", with: "p { color: teal; }")
        site.reply(site.pagePath, with: """
            <html><body><div id="head"></div><div id="bars"></div>
            <script>
            document.getElementById('head').innerHTML = '<link rel="stylesheet" href="/late.css">';
            document.getElementById('bars').innerHTML = '<p>up</p>';
            </script>
            </body></html>
            """)

        try await PageSourceOverride.with(site.source) {
            let tab: BrowserTab = try await Self.open(site)

            #expect(site.requests(for: "/late.css") == 1)
            #expect(Self.hasRule(tab, color: "teal"))
        }
    }

    @Test func loadingThePageAgainDownloadsItsStylesheetsAgain() async throws {
        let site: FakeSite = FakeSite()
        site.reply("/late.css", with: "p { color: olive; }")
        site.reply(site.pagePath, with: """
            <html><body><div id="head"></div>
            <script>document.getElementById('head').innerHTML = '<link rel="stylesheet" href="/late.css">';</script>
            </body></html>
            """)

        try await PageSourceOverride.with(site.source) {
            let tab: BrowserTab = try await Self.open(site)
            site.reply("/late.css", with: "p { color: purple; }")
            tab.load(site.url)
            try #require(await Self.pump({ site.requests(for: "/late.css") == 2 }))

            #expect(Self.hasRule(tab, color: "purple"))
            #expect(!Self.hasRule(tab, color: "olive"))
        }
    }

    private static func open(_ site: FakeSite) async throws -> BrowserTab {
        let browser: Browser = Browser()
        browser.usesAsyncLayout = false
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(site.url)
        browser.pauseAnimationTimer()
        let tab: BrowserTab = try #require(browser.activeTab)
        try #require(await pump({ tab.isLoaded }))
        return tab
    }

    private static func hasRule(_ tab: BrowserTab, color: String) -> Bool {
        tab.rootFrame.state.document.sheets.rules.contains(where: { (rule: RuleIndex.Rule) -> Bool in
            rule.2["color"] == color
        })
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

// MARK: - FakeSite

private final class FakeSite: @unchecked Sendable {
    let url: WebURL = WebURL("https://reuse-\(UUID().uuidString.lowercased()).example/\(UUID().uuidString)")
    private let lock: NSLock = NSLock()
    private var bodies: [String: String] = [:]
    private var counts: [String: Int] = [:]

    var pagePath: String { url.path }

    var source: PageSourceOverride.Source {
        return { [self] (_: String, path: String) in self.serve(path) }
    }

    func reply(_ path: String, with body: String) {
        lock.withLock({ bodies[path] = body })
    }

    func requests(for path: String) -> Int {
        lock.withLock({ counts[path] ?? 0 })
    }

    private func serve(_ path: String) -> (status: Int, headers: [String: String], content: String)? {
        lock.withLock({
            guard let body: String = bodies[path] else { return nil }
            counts[path, default: 0] += 1
            let type: String = path.hasSuffix(".css") ? "text/css" : "text/html"
            return (200, ["content-type": type], body)
        })
    }
}
