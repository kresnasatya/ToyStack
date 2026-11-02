import CoreGraphics
import Testing

@testable import Engine

@MainActor
struct PaintCullingTests {

    @Test func paintWindowIntersectsEdges() {
        let window: PaintWindow = PaintWindow(top: 100, bottom: 200)

        #expect(!window.intersects(Rect(left: 0, top: 0, right: 10, bottom: 90)))
        #expect(!window.intersects(Rect(left: 0, top: 210, right: 10, bottom: 300)))
        #expect(window.intersects(Rect(left: 0, top: 90, right: 10, bottom: 110)))
        #expect(window.intersects(Rect(left: 0, top: 190, right: 10, bottom: 210)))
    }

    @Test func offscreenTextIsCulledAndScrollRepaints() {
        let page: LayoutTestPage = tallPage()
        let frame: Frame = page.frame

        frame.setNeedsPaint()
        frame.paint()

        #expect(!displayTexts(frame.displayList).contains("bottommarker"))

        let maxScroll: CGFloat = frame.maxScroll
        frame.scroll = maxScroll
        #expect(frame.repaintForScroll())
        #expect(displayTexts(frame.displayList).contains("bottommarker"))
        #expect(frame.maxScroll == maxScroll)
    }

    @Test func scrollInsidePaintedWindowDoesNotRepaint() {
        let page: LayoutTestPage = tallPage()
        let frame: Frame = page.frame

        frame.setNeedsPaint()
        frame.paint()
        let before: String = displaySignature(frame.displayList)

        frame.scroll = 100
        #expect(!frame.repaintForScroll())
        #expect(displaySignature(frame.displayList) == before)
    }

    @Test func scrollPastPaintedWindowRepaints() {
        let page: LayoutTestPage = tallPage()
        let frame: Frame = page.frame

        frame.setNeedsPaint()
        frame.paint()

        frame.scroll = frame.maxScroll
        #expect(frame.repaintForScroll())
        #expect(displayTexts(frame.displayList).contains("bottommarker"))
    }

    @Test func fullPaintKeepsOffscreenContent() {
        let page: LayoutTestPage = tallPage()
        let frame: Frame = page.frame

        frame.setNeedsPaint()
        frame.paint(window: .full)

        #expect(displayTexts(frame.displayList).contains("bottommarker"))
    }

    @Test func cullingDoesNotShrinkScrollExtent() {
        let page: LayoutTestPage = tallPage()
        let frame: Frame = page.frame

        frame.setNeedsPaint()
        frame.paint()
        let extent: CGFloat = frame.maxScroll

        frame.scroll = extent
        _ = frame.repaintForScroll()

        #expect(frame.maxScroll == extent)
    }
}

@MainActor
private func tallPage() -> LayoutTestPage {
    return LayoutTestPage(
        html: """
        <div style="height: 4000px;"></div>
        <p id="bottom">bottommarker</p>
        """,
        rules: """
        body { display: block; }
        div, p { display: block; }
        """
    )
}

private func displayTexts(_ list: [DisplayOp]) -> [String] {
    var texts: [String] = []
    for op in list {
        if case .text(let text, _, _, _) = op { texts.append(text) }
    }
    return texts
}
