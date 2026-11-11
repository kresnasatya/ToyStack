import CoreGraphics
import Testing

@testable import Engine

/// Each block whose geometry is recomputed lands in exactly one
/// `layout.width.*` bucket, so a trace can tell which skip would pay off:
/// width changed, width kept but moved sideways, width kept but moved down,
/// or nothing changed at all.
@Suite(.serialized)
@MainActor
struct BlockWidthChangeMetricTests {

    @Test func narrowerWindowSeparatesWidthChangesFromBlocksThatOnlyMoveDown() throws {
        let words: String = Array(repeating: "word", count: 30).joined(separator: " ")
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <p id="para">\(words)</p>\
                <div id="card"><p>row one</p><p>row two</p></div>
                """,
            rules: """
                body { display: block; }
                p { display: block; }
                div { display: block; width: 200px; }
            """
        )
        let cardElement: ElementRef = try #require(page.firstElement(id: "card"))
        let card: LayoutID = try #require(page.firstBlockID(in: cardElement))
        let cardYBefore: CGFloat = page.tree.y(card)

        page.frame.setViewport(width: 300, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(page.tree.y(card) > cardYBefore, "the paragraph did not rewrap")
        #expect((metrics["layout.width.changed"]?.count ?? 0) > 0)
        #expect((metrics["layout.width.same.yMoved"]?.count ?? 0) == 3)
        #expect((metrics["layout.width.same.xMoved"]?.count ?? 0) == 0)
        expectEveryGeometryPassCountedOnce(metrics)
        expectIncrementalMatchesFull(page)
    }

    @Test func paddingChangeCountsBlocksThatOnlyMoveSideways() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="card"><p>row</p></div>"#,
            rules: """
                body { display: block; }
                p { display: block; }
                div { display: block; width: 200px; padding-left: 10px; }
            """
        )
        let card: ElementRef = try #require(page.firstElement(id: "card"))

        InlineStyle.set(card, property: "padding-left", value: "30px")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect((metrics["layout.width.same.xMoved"]?.count ?? 0) == 2)
        #expect((metrics["layout.width.changed"]?.count ?? 0) == 0)
        expectEveryGeometryPassCountedOnce(metrics)
        expectIncrementalMatchesFull(page)
    }

    @Test func widthPinnedToCurrentValueCountsAsUnmoved() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        let width: CGFloat = page.tree.width(block)

        InlineStyle.set(p, property: "width", value: "\(Int(width))px")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(width == width.rounded(), "the test needs a whole-pixel width")
        #expect((metrics["layout.width.same.unmoved"]?.count ?? 0) == 1)
        #expect((metrics["layout.width.changed"]?.count ?? 0) == 0)
        expectEveryGeometryPassCountedOnce(metrics)
        expectIncrementalMatchesFull(page)
    }
}

// MARK: - Helpers

private let widthBuckets: [String] = [
    "layout.width.changed",
    "layout.width.same.xMoved",
    "layout.width.same.yMoved",
    "layout.width.same.unmoved",
]

private func widthBucketTotal(_ metrics: [String: ProfileMetric]) -> Int {
    return widthBuckets.reduce(0) { total, name in total + (metrics[name]?.count ?? 0) }
}

private func expectEveryGeometryPassCountedOnce(
    _ metrics: [String: ProfileMetric],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let passes: Int = metrics["layout.visit.geometry"]?.count ?? 0
    #expect(passes > 0, sourceLocation: sourceLocation)
    #expect(widthBucketTotal(metrics) == passes, sourceLocation: sourceLocation)
}
