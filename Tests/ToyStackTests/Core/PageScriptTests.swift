import CoreGraphics
import Foundation
import JavaScriptCore
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct PageScriptTests {
    @Test func dataBlocksAreNeitherFetchedNorRun() async throws {
        let host: String = "page-script-\(UUID().uuidString.lowercased()).example"
        let page: String = """
            <html><body>
            <script id="__NEXT_DATA__" type="application/json">{"props":{"page":"/"}}</script>
            <script type="text/plain">window.plainRan = true</script>
            <script type="application/json" src="/data.js"></script>
            <script>window.classicRan = true</script>
            </body></html>
            """
        let result: JSValue? = try await load(host: host, files: [
            "/": page,
            "/data.js": "window.dataSrcRan = true",
        ], evaluate: "[typeof plainRan, typeof dataSrcRan, classicRan].join('|')")
        #expect(result?.toString() == "undefined|undefined|true")
    }

    @Test func eachScriptSeesItselfAsCurrentScript() async throws {
        let host: String = "page-script-\(UUID().uuidString.lowercased()).example"
        let page: String = """
            <html><body>
            <div id="host"></div>
            <script id="outer" src="/outer.js"></script>
            <script id="inline">window.inlineSaw = document.currentScript.id</script>
            </body></html>
            """
        let outer: String = """
            var inner = document.createElement('script');
            inner.setAttribute('src', '/inner.js');
            document.getElementById('host').appendChild(inner);
            window.outerSawAfterInner = document.currentScript.id;
            """
        let result: JSValue? = try await load(host: host, files: [
            "/": page,
            "/outer.js": outer,
            "/inner.js": "window.innerSaw = document.currentScript.getAttribute('src')",
        ], evaluate: "[outerSawAfterInner, innerSaw, inlineSaw, document.currentScript === null].join('|')")
        #expect(result?.toString() == "outer|/inner.js|inline|true")
    }

    private func load(host: String, files: [String: String], evaluate code: String) async throws -> JSValue? {
        return try await PageSourceOverride.with({ (scheme: String, path: String) in
            guard let body: String = files[path] else { return nil }
            let type: String = path.hasSuffix(".js") ? "text/javascript" : "text/html"
            return (200, ["content-type": type], body)
        }) {
            let browser: Browser = Browser()
            browser.usesAsyncLayout = false
            browser.resize(to: CGSize(width: 800, height: 600))
            browser.newTab(WebURL("https://\(host)/"))
            browser.pauseAnimationTimer()
            let tab: BrowserTab = try #require(browser.activeTab)
            let deadline: Date = Date().addingTimeInterval(10)
            while !tab.isLoaded, Date() < deadline {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
            #expect(tab.isLoaded)
            return tab.rootFrame.js.evaluate(code)
        }
    }
}
