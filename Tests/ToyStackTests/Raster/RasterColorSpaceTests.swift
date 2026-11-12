import CoreGraphics
import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct RasterColorSpaceTests {
    /// Core Animation converts a bitmap whose colour space differs from the
    /// screen's one pixel at a time in the commit: 0.42 ms per 256 × 256 tile,
    /// ~12 ms for the 30 tiles of one present during a drag. Every bitmap the
    /// presenter binds, tiles and composited effect layers alike, must already
    /// be in the screen's colour space.
    @Test func presentedBitmapsUseTheDisplayColorSpace() async throws {
        let id: String = UUID().uuidString
        let tracePath: String = NSTemporaryDirectory() + "raster-color-\(id).trace"
        let pagePath: String = NSTemporaryDirectory() + "raster-color-\(id).html"
        defer {
            try? FileManager.default.removeItem(atPath: tracePath)
            try? FileManager.default.removeItem(atPath: pagePath)
        }
        let paragraphs: String = (0..<20).map { (index: Int) -> String in
            "<p style=\"color: #a40000\">Paragraph \(index) with some red text.</p>"
        }.joined()
        let html: String = "<div style=\"opacity: 0.5\">faded</div>" + paragraphs
        try html.write(toFile: pagePath, atomically: true, encoding: .utf8)
        let displayP3: CGColorSpace = try #require(CGColorSpace(name: CGColorSpace.displayP3))

        let browser: Browser = Browser(tracePath: tracePath)
        defer { browser.stopAnimationTimer() }
        browser.usesAsyncLayout = false
        browser.displayColorSpace = displayP3
        browser.resize(to: CGSize(width: 800, height: 600))
        browser.newTab(WebURL("file://" + pagePath))
        browser.pauseAnimationTimer()

        #expect(await Self.pump({ browser.activeTab?.isLoaded == true }))
        #expect(await Self.settle(browser))

        let content: RenderedContent = browser.presentedFrame.content
        let tiles: [LayerPlacement] = content.placements.filter {
            if case .tile = $0.key { return true }
            return false
        }
        let effects: [LayerPlacement] = content.placements.filter {
            if case .composited = $0.key { return true }
            return false
        }
        #expect(!tiles.isEmpty)
        #expect(!effects.isEmpty)
        for placed in content.placements {
            #expect(placed.image.colorSpace?.name == displayP3.name, "\(placed.key)")
        }
    }

    private static func settle(_ browser: Browser) async -> Bool {
        let deadline: Date = Date().addingTimeInterval(10)
        while Date() < deadline {
            browser.advanceFrame()
            _ = await pump({ browser.isRenderIdle })
            if browser.isRenderIdle, !browser.presentedFrame.content.placements.isEmpty {
                return true
            }
        }
        return false
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
