import CoreGraphics
import Testing

@testable import Engine

/// A box with `overflow: scroll` keeps where it is scrolled to in the DOM.
/// Layout only decides how far it can scroll; paint shows the box at the
/// DOM offset, bounded by that range.
@Suite(.serialized)
@MainActor
struct ScrollBoxTests {
    /// A width-only resize reuses the layout inputs; the box must stay where
    /// the user scrolled it.
    @Test func relayoutKeepsTheScrollPosition() throws {
        let page: LayoutTestPage = Self.makePage()
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let target: ScrollBlockTarget = try #require(page.frame.state.layout.targets.blocks.first)
        page.frame.scrollAt(x: target.rect.left + 5, y: target.rect.top + 5, deltaY: -10)

        page.frame.setViewport(width: 400, height: 600)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(box.scrollOffsetY == 10)
        #expect(Self.paintedScrollOffsets(page) == [10], "the relayout moved the box back")
    }

    /// `scrollTop` from script only asks for a paint; the box must show the
    /// new offset without a layout.
    @Test func scriptScrollTopIsPainted() throws {
        let page: LayoutTestPage = Self.makePage()
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(
            script: "scrollTop",
            code: "document.getElementById('box').scrollTop = 25;"
        )

        #expect(Self.paintedScrollOffsets(page) == [25], "scrollTop did not reach the painted box")
    }

    /// An offset past the end of the content shows the end, not empty space.
    @Test func offsetPastTheEndShowsTheEnd() throws {
        let page: LayoutTestPage = Self.makePage()
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(
            script: "scrollTop",
            code: "document.getElementById('box').scrollTop = 100000;"
        )

        let id: LayoutID = try #require(box.ref.layoutID)
        let range: CGFloat = page.tree.blockContentHeight(id) - page.tree.height(id)
        #expect(range > 0)
        #expect(Self.paintedScrollOffsets(page) == [range])
    }

    // MARK: - Helpers

    /// The offset of every scroll effect in a fresh paint of the page.
    private static func paintedScrollOffsets(_ page: LayoutTestPage) -> [CGFloat] {
        page.frame.setNeedsPaint()
        page.frame.paint()
        return page.frame.displayList.compactMap({ op in
            guard case .beginEffect(let scope) = op, case .scroll(_, let offset) = scope.kind else {
                return nil
            }
            return offset
        })
    }

    private static func makePage() -> LayoutTestPage {
        let paragraphs: String = (0..<20).map { index in
            "<p>Paragraph \(index) inside the scroll box.</p>"
        }.joined()
        return LayoutTestPage(
            html: #"<div id="box">"# + paragraphs + "</div>",
            rules: """
                body { display: block; }
                p { display: block; }
                div { display: block; height: 50px; overflow: scroll; }
                """
        )
    }
}
