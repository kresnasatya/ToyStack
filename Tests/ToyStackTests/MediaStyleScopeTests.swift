import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct MediaStyleScopeTests {

    @Test func breakpointWithManyRulesRestylesOnlyMatchedNodes() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: makeManyRulePage(),
            rules: makeManyRuleStyles()
        )
        let target: ElementRef = try #require(page.firstElement(id: "target"))
        #expect(target.style.computed.text.color == BrowserColor(cssName: "red"))

        let total: Int = treeToList(page.frame.nodes).count
        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        // The layout phase resets the profiler. This test only observes the
        // style phase, so drop the queued layout and render style alone.
        page.frame.state.layout.tree.isDirty = false
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(metrics["style.scope.used"]?.count == 1)
        #expect(metrics["style.scope.none"] == nil)
        #expect(metrics["style.scope.rules"]?.count == 65)
        #expect(metrics["style.scope.direct"]?.count == 65)
        #expect((metrics["style.visited"]?.count ?? total) < total)
        #expect(target.style.computed.text.color != BrowserColor(cssName: "red"))
    }

    @Test func viewportPassStillAppliesOtherDirtyNodes() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="target">target</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                @media (min-width: 600px) { .absent { color: red; } }
                """
        )
        let target: ElementRef = try #require(page.firstElement(id: "target"))

        InlineStyle.set(target, property: "color", value: "blue")
        page.frame.setNeedsStyle(target.ref)
        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(target.style.computed.text.color == BrowserColor(cssName: "blue"))
    }
}

@MainActor
private func makeManyRulePage() -> String {
    let hits: String = (0..<65).map({ index -> String in
        if index == 0 {
            return #"<div class="k0" id="target">hit 0</div>"#
        }
        return #"<div class="k\#(index)">hit \#(index)</div>"#
    }).joined()
    let misses: String = (0..<50).map({ index -> String in
        return #"<div class="plain">miss \#(index)</div>"#
    }).joined()
    return #"<div class="container">\#(hits)\#(misses)</div>"#
}

@MainActor
private func makeManyRuleStyles() -> String {
    let media: String = (0..<65).map({ index -> String in
        return ".k\(index) { color: red; }"
    }).joined(separator: " ")
    return """
        html { width: 600px; }
        body { display: block; }
        div { display: block; }
        @media (min-width: 600px) { \(media) }
        """
}
