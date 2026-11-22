import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct CanvasColorTests {
    // The window behind the page is the canvas. Before, it was always white (or black
    // in dark mode), so a dark page showed a white strip around and below its content.
    @Test func windowTakesTheBodyBackground() async throws {
        let presented: CGColor = try await presentedCanvas(body: "background-color: rgb(10 10 10);")
        #expect(presented.components == BrowserColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255).cgColor.components)
    }

    @Test func windowStaysWhiteWithoutAPageBackground() async throws {
        let presented: CGColor = try await presentedCanvas(body: "color: red;")
        #expect(presented.components == BrowserColor(cssName: "white").cgColor.components)
    }

    private func presentedCanvas(body style: String) async throws -> CGColor {
        let host: String = "canvas-\(UUID().uuidString.lowercased()).example"
        let page: String = #"<html><body style="\#(style)"><p>text</p></body></html>"#
        return try await PageSourceOverride.with({ (scheme: String, path: String) in
            path == "/" ? (200, ["content-type": "text/html"], page) : nil
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
            browser.advanceFrame()
            return browser.presentedFrame.viewport.canvasColor
        }
    }
}
