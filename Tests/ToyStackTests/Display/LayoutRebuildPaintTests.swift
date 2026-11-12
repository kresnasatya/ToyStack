import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutRebuildPaintTests {
    private static let rows: String = (0..<12)
        .map({ (index: Int) -> String in
            "<p>block \(1000 + index) alpha beta gamma delta epsilon zeta eta theta</p>"
        })
        .joined()

    @Test func rebuildTreeAtNewWidthPaintsItsOwnLines() {
        let page: LayoutTestPage = LayoutTestPage(
            html: Self.rows,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        page.frame.paint()

        page.frame.setLayoutTree(nil)
        page.frame.setViewport(width: 320, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()
        profiler.reset()
        page.frame.paint()
        let painted: String = displaySignature(page.frame.displayList)
        let hits: Int = profiler.snapshot()["paint.cache.hit.lines"]?.count ?? 0

        page.frame.setNeedsPaint()
        page.frame.paint()
        let fresh: String = displaySignature(page.frame.displayList)

        #expect(hits == 0, "a brand-new tree reused \(hits) lines painted for the old tree")
        #expect(painted == fresh)
    }
}
