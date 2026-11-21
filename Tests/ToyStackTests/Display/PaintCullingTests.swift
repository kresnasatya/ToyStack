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
        frame.setScroll(maxScroll)
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

        frame.setScroll(100)
        #expect(!frame.repaintForScroll())
        #expect(displaySignature(frame.displayList) == before)
    }

    @Test func scrollPastPaintedWindowRepaints() {
        let page: LayoutTestPage = tallPage()
        let frame: Frame = page.frame

        frame.setNeedsPaint()
        frame.paint()

        frame.setScroll(frame.maxScroll)
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

        frame.setScroll(extent)
        _ = frame.repaintForScroll()

        #expect(frame.maxScroll == extent)
    }

    @Test func blocksFarBelowTheWindowAreLeftOut() {
        let page: LayoutTestPage = LayoutTestPage(
            html: (0..<200).map({ "<div class=\"row\" id=\"r\($0)\"></div>" }).joined(),
            rules: """
                body { display: block; }
                div { display: block; }
                .row { height: 100px; background-color: blue; }
                """
        )
        let frame: Frame = page.frame
        frame.setNeedsPaint()
        profiler.reset()
        frame.paint()

        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect((metrics["paint.scene.nodes"]?.count ?? 0) < 60)
        #expect(colorRects(frame.displayList, "blue").allSatisfy({ $0.top < 2000 }))

        frame.setScroll(frame.maxScroll)
        #expect(frame.repaintForScroll())
        #expect(colorRects(frame.displayList, "blue").contains(where: { $0.bottom > 19000 }))
    }

    @Test func floatHangingBelowAShortBlockStillPaints() {
        let page: LayoutTestPage = scrolledPage(
            child: #"<div id="hang"></div>"#,
            rules: "#hang { float: left; width: 50px; height: 5000px; background-color: green; }"
        )
        #expect(!colorRects(page.frame.displayList, "green").isEmpty)
    }

    @Test func absoluteChildPlacedIntoTheWindowStillPaints() {
        let page: LayoutTestPage = scrolledPage(
            child: #"<div id="abs"></div>"#,
            rules: "#abs { position: absolute; top: 3700px; height: 100px; width: 100px; background-color: purple; }"
        )
        #expect(!colorRects(page.frame.displayList, "purple").isEmpty)
    }

    @Test func transformedChildStillPaints() {
        let page: LayoutTestPage = scrolledPage(
            child: #"<div id="moved"></div>"#,
            rules: "#moved { height: 100px; background-color: teal; transform: translate(0px, 3700px); }"
        )
        #expect(hasTransformScope(page.frame.displayList))
    }

    @Test func noBlockIsLeftOutWhileAnAnimationRuns() throws {
        let page: LayoutTestPage = scrolledPage(
            child: #"<div id="moved"></div>"#,
            rules: "#moved { height: 100px; background-color: teal; }"
        )
        #expect(colorRects(page.frame.displayList, "teal").isEmpty)

        let moved: ElementRef = try #require(page.firstElement(id: "moved"))
        page.frame.addAnimation(TransformAnimation(
            animatedProperty: .transform,
            oldPoint: CGPoint.zero,
            newPoint: CGPoint(x: 0, y: 3700),
            timing: FrameTiming(totalFrames: 60, easing: .linear)
        ), to: moved.ref)
        page.frame.setNeedsPaint()
        page.frame.paint()

        #expect(hasTransformScope(page.frame.displayList))
    }

    @Test func growingAFloatIntoTheWindowPaintsIt() throws {
        let page: LayoutTestPage = scrolledPage(
            child: #"<div id="hang"></div>"#,
            rules: "#hang { float: left; width: 50px; height: 100px; background-color: green; }"
        )
        #expect(colorRects(page.frame.displayList, "green").isEmpty)

        let hang: ElementRef = try #require(page.firstElement(id: "hang"))
        InlineStyle.set(hang, property: "height", value: "5000px")
        page.frame.setNeedsStyle(hang.ref)
        page.frame.render()
        page.frame.setNeedsPaint()
        page.frame.paint()

        #expect(!colorRects(page.frame.displayList, "green").isEmpty)
    }
}

/// A short block at the top holds `child`; the page is scrolled far enough that
/// the block itself lies above the paint window.
@MainActor
private func scrolledPage(child: String, rules: String) -> LayoutTestPage {
    let page: LayoutTestPage = LayoutTestPage(
        html: #"<div id="top">\#(child)</div><div id="spacer"></div>"#,
        rules: """
            body { display: block; }
            div { display: block; }
            #top { height: 10px; }
            #spacer { height: 9000px; }
            """ + rules
    )
    page.frame.setScroll(3600)
    page.frame.setNeedsPaint()
    page.frame.paint()
    return page
}

private func colorRects(_ list: [DisplayOp], _ name: String) -> [Rect] {
    let color: BrowserColor = BrowserColor(cssName: name)
    var rects: [Rect] = []
    for op in list {
        if case .rect(let rect, let opColor) = op, opColor == color { rects.append(rect) }
    }
    return rects
}

/// A transformed block paints inside a transform scope that the compositor
/// moves, so the scope, not its contents, shows the block was built.
private func hasTransformScope(_ list: [DisplayOp]) -> Bool {
    return list.contains(where: { op in
        guard case .beginEffect(let scope) = op, case .transform = scope.kind else { return false }
        return true
    })
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
