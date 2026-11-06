import Foundation
import Testing

@testable import Engine

/// Owns a layout tree while it crosses a background queue. The tree is a value;
/// the box is only a transport for the async result.
private final class BackgroundLayoutTree: @unchecked Sendable {
    var tree: LayoutTree

    init(_ tree: LayoutTree) {
        self.tree = tree
    }
}

// Background layout records into the process-wide profiler. Running these tests
// beside suites that assert profiler counts makes those counts ambiguous, so
// they are opt-in: TOYSTACK_BACKGROUND_LAYOUT_TEST=1.
@Suite(.serialized)
@MainActor
struct BackgroundLayoutTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func backgroundLayoutMatchesMainThread() async throws {
        let html: String = (0..<80).map { index in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        let rules: String = """
            body { display: block; font-size: 24px; }
            p { display: block; }
            @media (max-width: 800px) { body { font-size: 18px; } }
            """
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: rules)
        let control: LayoutTestPage = LayoutTestPage(html: html, rules: rules)

        page.frame.setViewport(width: 220, height: 600)
        page.frame.setNeedsViewportResize()
        control.frame.setViewport(width: 220, height: 600)
        control.frame.setNeedsViewportResize()
        control.frame.render()

        let tree: LayoutTree = try #require(page.frame.document)
        let box: BackgroundLayoutTree = BackgroundLayoutTree(tree)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: LayoutTree = box.tree
                result.layoutDocument(availableWidth: 220, zoom: 1, pageZoom: 1)
                box.tree = result
                continuation.resume()
            }
        }

        let result: LayoutTree = box.tree
        expectAllLayoutFieldsClean(result)
        page.frame.setViewport(width: 220, height: 600)
        page.frame.setLayoutTree(result)

        let background: String = renderSignature(page.frame)
        let main: String = renderSignature(control.frame)
        #expect(
            background == main,
            "background layout diverged from main-thread layout"
        )
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func asyncFrameInstallsBackgroundLayout() async throws {
        let html: String = (0..<40).map { index in
            "<p>Paragraph \(index) has words that wrap.</p>"
        }.joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; }"
        )
        let control: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; }"
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser

        page.frame.setViewport(width: 220, height: 600)
        page.frame.setNeedsViewportResize()
        control.frame.setViewport(width: 220, height: 600)
        control.frame.setNeedsViewportResize()
        control.frame.render()

        page.frame.render()
        #expect(page.frame.isLayoutInFlight)
        for _ in 0..<200 where page.frame.isLayoutInFlight {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(!page.frame.isLayoutInFlight)

        let background: String = renderSignature(page.frame)
        let main: String = renderSignature(control.frame)
        #expect(background == main, "async frame diverged from main-thread layout")
    }
}
