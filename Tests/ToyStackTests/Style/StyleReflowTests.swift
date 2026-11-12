import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleReflowTests {
    private func page() -> LayoutTestPage {
        return LayoutTestPage(
            html: #"<p id="p">hello</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; width: 300px; }
                """
        )
    }

    @Test func recoloringTextSkipsLayout() throws {
        let page: LayoutTestPage = page()
        let p: ElementRef = try #require(page.firstElement(id: "p"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        let width: CGFloat = page.tree.width(block)

        InlineStyle.set(p, property: "color", value: "red")
        page.frame.setNeedsStyle(page.ref(of: p))
        profiler.reset()
        page.frame.render()

        #expect(profiler.snapshot()["layout.visited"] == nil)
        #expect(profiler.snapshot()["layout.inputs.build"] == nil)
        #expect(page.tree.width(block) == width)
        page.frame.paint()
        #expect(page.frame.displayList.contains(where: { op in
            guard case .text(_, _, let color, _) = op else { return false }
            return color == BrowserColor(cssName: "red")
        }))
    }

    @Test func widthChangeStillLaysOut() throws {
        let page: LayoutTestPage = page()
        let p: ElementRef = try #require(page.firstElement(id: "p"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))

        InlineStyle.set(p, property: "width", value: "120px")
        page.frame.setNeedsStyle(page.ref(of: p))
        profiler.reset()
        page.frame.render()

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect(page.tree.width(block) == 120)
    }
}
