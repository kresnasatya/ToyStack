import CoreGraphics
import Foundation
import Testing

@testable import Engine

// Opt-in for the same reason as BackgroundLayoutTests.
@Suite(.serialized)
@MainActor
struct AsyncResizeRestartTests {
    /// A pass that finishes after the window moved on is installed and painted
    /// at once, and the pass for the current width starts at once: no
    /// frame-clock tick is needed between them.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func finishedPassIsPaintedAndTheNextStartsWithoutATick() async throws {
        let path: String = NSTemporaryDirectory() + "no-tick-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage(tracePath: path)

        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        #expect(page.frame.isLayoutInFlight)
        // The pointer moves on while the 400 pass runs. From here on, no tick.
        page.tab.resize(width: 300, height: 600)
        try await Self.settle(page)

        let installed: CGSize = page.frame.installedLayoutSize
        let painted: CGSize = page.frame.paintedLayoutSize
        #expect(installed.width == 300, "no pass ran for the latest width")
        #expect(painted.width == 300, "the latest width was not painted")

        browser.measure.close()
        let events: [[String: Any]] = try Self.traceEvents(path)
        let superseded: [Int] = events
            .filter({ $0["name"] as? String == "layout.async.superseded" })
            .compactMap({ ($0["args"] as? [String: Any])?["width"] as? Int })
        let paints: Int = events.filter({
            $0["name"] as? String == "BrowserTab.paint" && $0["ph"] as? String == "B"
        }).count
        #expect(superseded == [400], "the 400 pass was not installed as an intermediate layout")
        #expect(paints == 2, "expected the 400 and the 300 layouts painted, got \(paints) paints")
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

    /// A pass that only changes the width keeps the same scroll targets.
    /// Installing it refreshes their rects instead of walking the whole tree,
    /// and the refreshed rects follow the new layout.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func widthOnlyInstallReusesScrollTargets() async throws {
        let path: String = NSTemporaryDirectory() + "scroll-reuse-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage(
            html: "<div></div>" + Self.paragraphs,
            rules: Self.scrollRules,
            tracePath: path
        )
        var widths: [CGFloat] = []
        for width in [400, 300] {
            page.tab.resize(width: CGFloat(width), height: 600)
            page.frame.runAnimationFrame()
            try await Self.settle(page)
            let target: ScrollBlockTarget = try Self.onlyScrollBlock(page)
            widths.append(target.rect.right - target.rect.left)
        }
        #expect(widths[0] > widths[1], "the scroll box rect did not follow the viewport: \(widths)")

        browser.measure.close()
        let rebuilt: [Int] = try Self.scrollTargetSamples(path)
        try #require(rebuilt.count == 2, "expected one sample per install, got \(rebuilt)")
        #expect(rebuilt == [0, 0], "a width-only install walked the whole tree: \(rebuilt)")
    }

    /// A box that becomes scrollable while a pass runs: the change bumps the
    /// target revision after the pass recorded its own. The list must still
    /// pick the box up once the follow-up pass is installed.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func boxMadeScrollableDuringAPassBecomesATarget() async throws {
        let path: String = NSTemporaryDirectory() + "scroll-overflow-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage(
            html: "<div></div>" + Self.paragraphs,
            rules: Self.blockRules + " div { display: block; height: 20px; }",
            tracePath: path
        )
        let box: ElementRef = try #require(page.firstElement(tag: "div"))
        #expect(page.frame.state.layout.targets.blocks.isEmpty)

        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        #expect(page.frame.isLayoutInFlight)
        InlineStyle.set(box, property: "overflow", value: "scroll")
        page.frame.setNeedsRender()
        page.frame.runAnimationFrame()
        try await Self.settle(page)

        _ = try Self.onlyScrollBlock(page)
        browser.measure.close()
        let rebuilt: [Int] = try Self.scrollTargetSamples(path)
        #expect(rebuilt.last == 1, "the install after the change reused the old list: \(rebuilt)")
    }

    /// A removed scroll box must leave the target list.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func removedScrollBoxLeavesTheTargets() async throws {
        let path: String = NSTemporaryDirectory() + "scroll-removed-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (page, browser): (LayoutTestPage, Browser) = Self.makeAsyncPage(
            html: #"<section id="box"><div></div></section>"# + Self.paragraphs,
            rules: Self.scrollRules,
            tracePath: path
        )
        page.tab.resize(width: 400, height: 600)
        page.frame.runAnimationFrame()
        try await Self.settle(page)
        _ = try Self.onlyScrollBlock(page)

        page.frame.js.run(
            script: "removeChild",
            code: """
                var box = document.getElementById('box');
                box.removeChild(box.children[0]);
            """
        )
        page.frame.runAnimationFrame()
        try await Self.settle(page)

        let blocks: [ScrollBlockTarget] = page.frame.state.layout.targets.blocks
        #expect(blocks.isEmpty, "a removed scroll box is still a target")
        browser.measure.close()
        let rebuilt: [Int] = try Self.scrollTargetSamples(path)
        #expect(rebuilt.last == 1, "the install after the removal reused the old list: \(rebuilt)")
    }

    // MARK: - Helpers

    private static let paragraphs: String = (0..<40).map { index in
        "<p>Paragraph \(index) has words that wrap when the viewport is narrow.</p>"
    }.joined()

    private static let blockRules: String = "body { display: block; } p { display: block; }"

    /// A `div` is a scroll target whose width follows the viewport.
    private static let scrollRules: String = blockRules
        + " section { display: block; }"
        + " div { display: block; height: 20px; overflow: scroll; }"

    /// The tab keeps a weak reference to the browser; the caller holds it.
    private static func makeAsyncPage(
        html: String = paragraphs,
        rules: String = blockRules,
        tracePath: String? = nil
    ) -> (LayoutTestPage, Browser) {
        let page: LayoutTestPage = LayoutTestPage(html: html, rules: rules)
        let browser: Browser = Browser(tracePath: tracePath)
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

    private static func traceEvents(_ path: String) throws -> [[String: Any]] {
        let data: Data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root: [String: Any] = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(root["traceEvents"] as? [[String: Any]])
    }

    /// `rebuilt` of every `layout.async.scrollTargets` sample, in order.
    private static func scrollTargetSamples(_ path: String) throws -> [Int] {
        return try traceEvents(path)
            .filter({ $0["name"] as? String == "layout.async.scrollTargets" })
            .compactMap({ ($0["args"] as? [String: Any])?["rebuilt"] as? Int })
    }

    /// The only scroll block target, checked against the installed tree.
    private static func onlyScrollBlock(_ page: LayoutTestPage) throws -> ScrollBlockTarget {
        let tree: LayoutTree = try #require(page.frame.document)
        let blocks: [ScrollBlockTarget] = page.frame.state.layout.targets.blocks
        #expect(blocks.count == 1, "expected one scroll block target, got \(blocks.count)")
        let target: ScrollBlockTarget = try #require(blocks.first)
        #expect(target.rect == tree.selfRect(target.layout), "the target rect is stale")
        return target
    }
}
