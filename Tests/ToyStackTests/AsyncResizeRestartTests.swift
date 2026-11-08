import CoreGraphics
import Foundation
import Testing

@testable import Engine

// Opt-in for the same reason as BackgroundLayoutTests.
@Suite(.serialized)
@MainActor
struct AsyncResizeRestartTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func frameClockRestartsLayoutAfterAStaleResult() async throws {
        let html: String = (0..<40).map { index in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; }"
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        // The page loaded and painted before the resize.
        page.frame.clearPaintRequest()

        // A layout for 400 starts.
        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        let started: Bool = page.frame.isLayoutInFlight
        #expect(started)

        // Resize while it runs; this tick consumes the render request.
        page.tab.resize(width: 300, height: 600)
        page.frame.runAnimationFrame()
        let stillRunning: Bool = page.frame.isLayoutInFlight
        #expect(stillRunning)

        // The 400 result installs as an intermediate layout. Nothing else invalidates.
        let deadline: Date = Date().addingTimeInterval(5)
        while page.frame.isLayoutInFlight, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        page.frame.clearPaintRequest()

        // The frame clock alone must start the pass for the latest width.
        page.frame.runAnimationFrame()
        let restarted: Bool = page.frame.isLayoutInFlight
        let asyncOn: Bool = browser.usesAsyncLayout   // also keeps the weak tab.browser alive
        #expect(asyncOn)
        #expect(restarted, "the final width never restarted after the intermediate install")
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func resizeDuringAPassInstallsItsResultThenLaysOutTheLatestWidth() async throws {
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage()

        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        #expect(page.frame.isLayoutInFlight)

        // The pointer keeps moving while the pass runs. The pass must still
        // finish, or a drag never shows a new layout.
        page.tab.resize(width: 300, height: 600)
        try await Self.settle(page)
        let intermediate: CGSize = page.frame.installedLayoutSize
        #expect(intermediate.width == 400, "the pass for 400 was dropped instead of installed")

        // The frame clock lays out the width the window has now.
        page.frame.runAnimationFrame()
        let restarted: Bool = page.frame.isLayoutInFlight
        #expect(restarted, "no pass started for the latest width")
        try await Self.settle(page)
        let final: CGSize = page.frame.installedLayoutSize
        #expect(final.width == 300)
        #expect(browser.usesAsyncLayout)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func passBackAtItsStartingWidthNeedsNoFollowUp() async throws {
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage()

        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        page.tab.resize(width: 300, height: 600)
        page.tab.resize(width: 400, height: 600)
        try await Self.settle(page)
        let installed: CGSize = page.frame.installedLayoutSize
        #expect(installed.width == 400, "a pass for the current width was not installed")

        page.frame.runAnimationFrame()
        let restarted: Bool = page.frame.isLayoutInFlight
        #expect(!restarted, "the window is back at 400, so no other pass is needed")
        #expect(browser.usesAsyncLayout)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func tabPaintsTheIntermediateLayoutWhileTheNextPassRuns() async throws {
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage()

        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        page.tab.resize(width: 300, height: 600)
        try await Self.settle(page)

        // The pass for 300 starts. Only the viewport moved, so the 400 layout
        // is still a valid picture of the document and must reach the screen.
        page.frame.runAnimationFrame()
        page.tab.runAnimationFrame()
        let running: Bool = page.frame.isLayoutInFlight
        let painted: CGSize = page.frame.paintedLayoutSize
        #expect(running)
        #expect(painted.width == 400, "the intermediate layout was never painted")
        try await Self.settle(page)
        #expect(browser.usesAsyncLayout)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func contentChangeDuringAPassHoldsPaintBack() async throws {
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage()

        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        try await Self.settle(page)
        page.tab.resize(width: 300, height: 600)
        page.frame.runAnimationFrame()
        #expect(page.frame.isLayoutInFlight)

        // The document changes while the pass runs. The installed tree no
        // longer matches it, so the tab must wait for the pass.
        page.frame.setNeedsLayout()
        page.frame.setNeedsPaint()
        page.tab.runAnimationFrame()
        let stillWaiting: Bool = page.frame.state.display.paint.isNeeded
        #expect(stillWaiting, "painted a layout that no longer matches the document")
        try await Self.settle(page)
        #expect(browser.usesAsyncLayout)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func widthOnlyResizeReusesLayoutInputsInTheAsyncPath() async throws {
        let html: String = (0..<40).map { index in
            "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
        }.joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: html,
            rules: "body { display: block; } p { display: block; }"
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        page.frame.clearPaintRequest()

        // The first pass builds the inputs and installs them.
        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        let deadline: Date = Date().addingTimeInterval(5)
        while page.frame.isLayoutInFlight, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        // Nothing but the width changed, so the next pass has nothing to rebuild.
        page.tab.resize(width: 300, height: 600)
        profiler.reset()
        page.frame.runAnimationFrame()
        let reused: Int = profiler.snapshot()["layout.inputs.reused"]?.count ?? 0
        let asyncOn: Bool = browser.usesAsyncLayout
        #expect(asyncOn)
        #expect(reused > 0, "the async pass rebuilt every layout input for a width change")
    }

    /// Each background pass must leave the tree ready for the next one: the
    /// next pass only updates the fields that depend on what changed, so a
    /// lost dependency shows up as a stale layout one pass later.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func consecutiveBackgroundPassesMatchAFullLayout() async throws {
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage()
        for width in [400, 300, 520, 360] {
            page.tab.resize(width: CGFloat(width), height: 600)
            page.frame.runAnimationFrame()
            try await Self.settle(page)
            #expect(page.frame.installedLayoutSize.width == CGFloat(width))
        }

        let control: LayoutTestPage = LayoutTestPage(
            html: Self.paragraphs,
            rules: "body { display: block; } p { display: block; }"
        )
        control.frame.setViewport(width: 360, height: 600)
        control.frame.setNeedsViewportResize()
        control.frame.setLayoutTree(nil)
        control.frame.setNeedsLayout()
        control.frame.render()
        #expect(renderSignature(page.frame) == renderSignature(control.frame))
        #expect(browser.usesAsyncLayout)
    }

    // MARK: - Helpers

    private static let paragraphs: String = (0..<40).map { index in
        "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
    }.joined()

    /// The tab keeps a weak reference to the browser; the caller holds it.
    private static func makeAsyncPage() -> (LayoutTestPage, Browser) {
        let page: LayoutTestPage = LayoutTestPage(
            html: paragraphs,
            rules: "body { display: block; } p { display: block; }"
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))
        page.frame.clearPaintRequest()
        return (page, browser)
    }

    private static func settle(_ page: LayoutTestPage) async throws {
        let deadline: Date = Date().addingTimeInterval(5)
        while page.frame.isLayoutInFlight, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(!page.frame.isLayoutInFlight)
    }
}
