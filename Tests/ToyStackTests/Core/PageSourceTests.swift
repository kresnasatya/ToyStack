import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct PageSourceTests {
    // The app installs its page source from SwiftUI, on the main actor. A
    // script that changes the DOM makes the frame wait for its stylesheets on
    // the main thread, so a source that also needs the main thread would
    // freeze the page forever.
    @Test func pageSourceInstalledOnTheMainActorDoesNotFreezeAPageThatChangesItsDOM() async throws {
        let host: String = "page-source-\(UUID().uuidString.lowercased()).example"
        let pagePath: String = "/\(UUID().uuidString)"
        let stylePath: String = "/\(UUID().uuidString).css"
        let page: String = """
            <html><head><link rel="stylesheet" href="\(stylePath)"></head>
            <body><div id="bars"></div>
            <script>document.getElementById('bars').innerHTML = '<p>up</p>';</script>
            </body></html>
            """

        let loaded: Bool = try await PageSourceOverride.with({ (scheme: String, requested: String) in
            switch requested {
            case pagePath: return (200, [:], page)
            case stylePath: return (200, ["content-type": "text/css"], "p { color: red; }")
            default: return nil
            }
        }) {
            let browser: Browser = Browser()
            browser.usesAsyncLayout = false
            browser.resize(to: CGSize(width: 800, height: 600))
            browser.newTab(WebURL("https://\(host)\(pagePath)"))
            browser.pauseAnimationTimer()
            let tab: BrowserTab = try #require(browser.activeTab)
            return await Self.pump({ tab.isLoaded })
        }

        #expect(loaded)
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
