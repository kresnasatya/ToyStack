import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutCancellationTests {
    private static let rules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; height: 10px; }
        """
    private static let html: String = #"<div>1</div><div>2</div><div>3</div><div>4</div>"#

    @Test func cancelledPassVisitsNoBlocks() {
        let page: LayoutTestPage = LayoutTestPage(html: Self.html, rules: Self.rules)
        var tree: LayoutTree = page.tree
        let token: LayoutCancellation = LayoutCancellation()
        tree.setCancellation(token)
        tree.markDocumentGeometryDirty()
        token.cancel()
        profiler.reset()

        tree.layoutDocument(availableWidth: 400, zoom: 1.0, pageZoom: 1.0)

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 0)
    }

    @Test func uncancelledPassStillVisitsBlocks() {
        let page: LayoutTestPage = LayoutTestPage(html: Self.html, rules: Self.rules)
        var tree: LayoutTree = page.tree
        tree.setCancellation(LayoutCancellation())
        tree.markDocumentGeometryDirty()
        profiler.reset()

        tree.layoutDocument(availableWidth: 400, zoom: 1.0, pageZoom: 1.0)

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
    }
}
