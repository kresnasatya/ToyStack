import CoreGraphics
import Foundation
import Testing

@testable import Engine

// Background layout records into the process-wide profiler, so this suite is
// opt-in for the same reason as BackgroundLayoutTests.
@Suite(.serialized)
@MainActor
struct AsyncResizeStyleChangeTests {
    /// A flip pass starts a background job, then the next resize makes that
    /// job stale. The job already took the font-size change out of the DOM;
    /// the pass for the final width must still know the font changed.
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func staleBackgroundJobStillAppliesTheFontFlip() async throws {
        let paragraph: String = String(
            repeating: "alpha beta gamma delta epsilon zeta eta theta ",
            count: 20
        )
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p id=\"p\">\(paragraph)</p>",
            rules: """
                html { width: 600px; font-size: 24px; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                body { display: block; }
                p { display: block; }
                """
        )
        let browser: Browser = Browser()
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        func settle() async throws {
            let deadline: Date = Date().addingTimeInterval(5)
            while page.frame.isLayoutInFlight, Date() < deadline {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
        }

        page.tab.resize(width: 900, height: page.frame.frameHeight)
        page.frame.render()
        try await settle()

        // The flip pass starts a job for 700. The next resize makes it stale
        // before it can install.
        page.tab.resize(width: 700, height: page.frame.frameHeight)
        page.frame.render()
        page.tab.resize(width: 650, height: page.frame.frameHeight)

        for _ in 0..<6 {
            page.frame.runAnimationFrame()
            try await settle()
        }
        #expect(!page.frame.isLayoutInFlight)

        let doc: LayoutTree = try #require(page.frame.document)
        var boxSizes: Set<CGFloat> = []
        var ownerSizes: Set<CGFloat> = []
        for line in treeToList(doc, doc.rootID) where doc.isLine(line) {
            guard let boxes: [InlineBox] = doc.currentInlineBoxes(line) else { continue }
            for box in boxes {
                boxSizes.insert(box.text.font.size)
                ownerSizes.insert(
                    DOMRef(id: box.dom, dom: doc.dom)
                        .inheritedStyleOwner.style.computed.text.font.size
                )
            }
        }
        #expect(doc.width(doc.rootID) < 650, "the pass for the final width did not run")
        #expect(boxSizes == ownerSizes, "line boxes kept the old font after a stale job")
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["TOYSTACK_BACKGROUND_LAYOUT_TEST"] == "1"
        )
    )
    func pendingFontFlipDoesNotForceAFullInputRebuild() async throws {
        let paragraph: String = String(
            repeating: "alpha beta gamma delta epsilon zeta eta theta ",
            count: 20
        )
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p id=\"p\">\(paragraph)</p>",
            rules: """
                html { width: 600px; font-size: 24px; }
                @media (max-width: 800px) { html { font-size: 18px; } }
                body { display: block; }
                p { display: block; }
                """
        )
        let path: String = NSTemporaryDirectory() + "pending-flip-\(UUID().uuidString).trace"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let browser: Browser = Browser(tracePath: path)
        browser.usesAsyncLayout = true
        page.tab.browser = browser
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        func settle() async throws {
            let deadline: Date = Date().addingTimeInterval(5)
            while page.frame.isLayoutInFlight, Date() < deadline {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
        }

        page.tab.resize(width: 900, height: page.frame.frameHeight)
        page.frame.render()
        try await settle()

        // The flip pass starts a job for 700. The next resize makes it stale
        // before it can install.
        page.tab.resize(width: 700, height: page.frame.frameHeight)
        page.frame.render()
        page.tab.resize(width: 650, height: page.frame.frameHeight)

        for _ in 0..<6 {
            page.frame.runAnimationFrame()
            try await settle()
        }
        #expect(!page.frame.isLayoutInFlight)

        let doc: LayoutTree = try #require(page.frame.document)
        var boxSizes: Set<CGFloat> = []
        var ownerSizes: Set<CGFloat> = []
        for line in treeToList(doc, doc.rootID) where doc.isLine(line) {
            guard let boxes: [InlineBox] = doc.currentInlineBoxes(line) else { continue }
            for box in boxes {
                boxSizes.insert(box.text.font.size)
                ownerSizes.insert(
                    DOMRef(id: box.dom, dom: doc.dom)
                        .inheritedStyleOwner.style.computed.text.font.size
                )
            }
        }
        #expect(doc.width(doc.rootID) < 650, "the pass for the final width did not run")
        #expect(boxSizes == ownerSizes, "line boxes kept the old font after a stale job")

        browser.measure.close()
        let trace: String = try String(contentsOfFile: path, encoding: .utf8)
        let events: [String] = trace.components(separatedBy: "\"ph\":").filter({
            $0.contains("layout.inputs.decision")
        })
        let reusedWithPending: Bool = events.contains(where: {
            $0.contains("\"pendingChanges\": 1") && $0.contains("\"reused\": 1")
        })
        #expect(reusedWithPending, "a job with pending style changes rebuilt every input")
    }
}
