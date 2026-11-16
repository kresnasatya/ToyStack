import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct BorderPaintTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        div { display: block; height: 20px; }
        """

    private func paintedBox(_ page: LayoutTestPage, id: String) throws -> Rect {
        page.frame.setNeedsPaint()
        page.frame.paint()
        let layout: LayoutID = try #require(page.firstElement(id: id)?.ref.layoutID)
        return page.tree.selfRect(layout)
    }

    private func fills(_ page: LayoutTestPage) -> [(rect: Rect, color: BrowserColor)] {
        return page.frame.displayList.compactMap { op in
            guard case .rect(let rect, let color) = op else { return nil }
            return (rect, color)
        }
    }

    /// Top and bottom span the whole border box; left and right fill the
    /// height between them.
    private func sideRects(_ box: Rect, _ widths: EdgeInsets) -> [Rect] {
        let innerTop: CGFloat = box.top + widths.top
        let innerBottom: CGFloat = box.bottom - widths.bottom
        return [
            Rect(left: box.left, top: box.top, right: box.right, bottom: innerTop),
            Rect(left: box.right - widths.right, top: innerTop, right: box.right, bottom: innerBottom),
            Rect(left: box.left, top: innerBottom, right: box.right, bottom: box.bottom),
            Rect(left: box.left, top: innerTop, right: box.left + widths.left, bottom: innerBottom),
        ]
    }

    private func borderSides(_ page: LayoutTestPage) -> [BorderSidePaint] {
        return page.frame.displayList.compactMap { op in
            guard case .borderSide(let side) = op else { return nil }
            return side
        }
    }

    private func corners(_ rect: Rect) -> [Point] {
        return [
            Point(x: rect.left, y: rect.top),
            Point(x: rect.right, y: rect.top),
            Point(x: rect.right, y: rect.bottom),
            Point(x: rect.left, y: rect.bottom),
        ]
    }

    @Test func borderFillsEachSideInsideTheBorderBox() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { padding: 6px; border: 4px solid red; }"
        )
        let box: Rect = try paintedBox(page, id: "box")

        #expect(fills(page).map(\.rect) == sideRects(box, EdgeInsets(top: 4, right: 4, bottom: 4, left: 4)))
        #expect(!page.frame.displayList.contains(where: { $0.name == "outline" }))
    }

    /// Where two colors meet, the corner splits on the line from the outer
    /// corner to the padding-box corner, inside the region CSS Backgrounds 3
    /// §4.4 allows for the change.
    @Test func eachSidePaintsItsOwnWidthAndColorUpToTheCornerLine() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { border-style: solid; border-width: 1px 2px 3px 4px;
                       border-color: red green blue gold; }
                """
        )
        let box: Rect = try paintedBox(page, id: "box")
        let outer: [Point] = corners(box)
        let inner: [Point] = corners(box.inset(by: EdgeInsets(top: 1, right: 2, bottom: 3, left: 4)))
        let painted: [BorderSidePaint] = borderSides(page)

        #expect(painted.map(\.region) == [
            Quad(a: outer[0], b: outer[1], c: inner[1], d: inner[0]),
            Quad(a: outer[1], b: outer[2], c: inner[2], d: inner[1]),
            Quad(a: outer[2], b: outer[3], c: inner[3], d: inner[2]),
            Quad(a: outer[3], b: outer[0], c: inner[0], d: inner[3]),
        ])
        #expect(painted.map(\.color) == ["red", "green", "blue", "gold"].map { BrowserColor(cssName: $0) })
        #expect(painted.allSatisfy({ $0.dash == nil }))
        #expect(fills(page).isEmpty)
    }

    @Test func sideWithoutAStyleIsNotPainted() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { border-bottom: 2px solid gray; }"
        )
        let box: Rect = try paintedBox(page, id: "box")

        #expect(fills(page).map(\.rect) == [
            Rect(left: box.left, top: box.bottom - 2, right: box.right, bottom: box.bottom),
        ])
    }

    @Test func zoomedBorderIsPaintedAtTheZoomedWidth() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { zoom: 2; border: 3px solid red; }"
        )
        let box: Rect = try paintedBox(page, id: "box")

        #expect(fills(page).map(\.rect) == sideRects(box, EdgeInsets(top: 6, right: 6, bottom: 6, left: 6)))
    }

    @Test func backgroundCoversTheBorder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { border: 5px solid red; background-color: gold; }"
        )
        page.frame.setNeedsPaint()
        page.frame.paint()
        let box: LayoutID = try #require(page.firstElement(id: "box")?.ref.layoutID)
        let x: CGFloat = page.tree.x(box)
        let y: CGFloat = page.tree.y(box)
        let borderBox: Rect = Rect(
            left: x - 5,
            top: y - 5,
            right: x + page.tree.width(box) + 5,
            bottom: y + page.tree.height(box) + 5
        )

        #expect(fills(page).first?.rect == borderBox)
        #expect(fills(page).first?.color == BrowserColor(cssName: "gold"))
    }

    @Test func overflowHiddenClipsInsideTheBorder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div></div></div>"#,
            rules: Self.baseRules + """
                #box { overflow: hidden; border-style: solid; border-width: 1px 2px 3px 4px; }
                """
        )
        let box: Rect = try paintedBox(page, id: "box")

        let clips: [Rect] = page.frame.displayList.compactMap { op in
            guard case .beginEffect(let scope) = op, case .clip(let shape) = scope.kind else {
                return nil
            }
            return shape.rect
        }
        #expect(clips == [Rect(left: box.left + 4, top: box.top + 1, right: box.right - 2, bottom: box.bottom - 3)])
    }

    @Test func scrollBoxScrollsInsideTheBorder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div></div><div></div></div>"#,
            rules: Self.baseRules + "#box { overflow: scroll; border: 5px solid red; }"
        )
        let box: Rect = try paintedBox(page, id: "box")

        let scrollports: [Rect] = page.frame.displayList.compactMap { op in
            guard case .beginEffect(let scope) = op, case .scroll(let shape, _) = scope.kind else {
                return nil
            }
            return shape.rect
        }
        #expect(scrollports == [Rect(left: box.left + 5, top: box.top + 5, right: box.right - 5, bottom: box.bottom - 5)])
    }

    @Test func roundedBorderIsOneRingBetweenTheCurves() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { border: 4px solid red; border-radius: 10px; }"
        )
        let box: Rect = try paintedBox(page, id: "box")

        let rings: [(outer: ClipShape, inner: ClipShape, color: BrowserColor)] =
            page.frame.displayList.compactMap { op in
                guard case .ring(let outer, let inner, let color) = op else { return nil }
                return (outer, inner, color)
            }
        #expect(rings.count == 1)
        #expect(rings.first?.outer.rect == box)
        #expect(rings.first?.outer.radii == .uniform(.px(10)))
        #expect(rings.first?.inner.rect == Rect(left: box.left + 4, top: box.top + 4, right: box.right - 4, bottom: box.bottom - 4))
        #expect(rings.first?.inner.radii == .uniform(.px(6)))
        #expect(rings.first?.color == BrowserColor(cssName: "red"))
        #expect(fills(page).isEmpty)
    }

    @Test func roundedBorderPaintsEachSideInItsOwnColor() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + """
                #box { height: 40px; border: 4px solid; border-color: red green blue gold;
                       border-radius: 12px; }
                """
        )
        let box: Rect = try paintedBox(page, id: "box")
        let pixels: PagePixels = PagePixels(page.frame.displayList, width: 700, height: 100)
        let middleX: CGFloat = (box.left + box.right) / 2
        let middleY: CGFloat = (box.top + box.bottom) / 2

        #expect(pixels.matches(BrowserColor(cssName: "red"), x: middleX, y: box.top + 2))
        #expect(pixels.matches(BrowserColor(cssName: "green"), x: box.right - 2, y: middleY))
        #expect(pixels.matches(BrowserColor(cssName: "blue"), x: middleX, y: box.bottom - 2))
        #expect(pixels.matches(BrowserColor(cssName: "gold"), x: box.left + 2, y: middleY))
        // Either side of the top-left corner line, still inside the curve.
        #expect(pixels.matches(BrowserColor(cssName: "red"), x: box.left + 9, y: box.top + 2))
        #expect(pixels.matches(BrowserColor(cssName: "gold"), x: box.left + 2, y: box.top + 9))
        #expect(!page.frame.displayList.contains(where: { $0.name == "ring" }))
    }

    @Test func overflowHiddenClipsToTheInnerCurve() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div></div></div>"#,
            rules: Self.baseRules + "#box { overflow: hidden; border: 4px solid red; border-radius: 10px; }"
        )
        _ = try paintedBox(page, id: "box")

        let radii: [CornerRadii] = page.frame.displayList.compactMap { op in
            guard case .beginEffect(let scope) = op, case .clip(let shape) = scope.kind else {
                return nil
            }
            return shape.radii
        }
        #expect(radii == [.uniform(.px(6))])
    }

    @Test func imageBorderIsPaintedAroundItsPadding() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><img id="photo" width="50" height="40"></p>"#,
            rules: Self.baseRules + "p { display: block; } #photo { padding: 4px; border: 3px solid red; }"
        )
        page.frame.setNeedsPaint()
        page.frame.paint()
        let image: ElementRef = try #require(page.firstElement(id: "photo"))
        let box: Rect = page.tree.selfRect(try #require(page.firstEmbedID(in: image)))

        #expect(fills(page).map(\.rect) == sideRects(box, EdgeInsets(top: 3, right: 3, bottom: 3, left: 3)))
    }

    @Test func iframeBorderFillsTheRoomAroundItsContent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p><iframe id="frame" width="100" height="50"></iframe></p>"#,
            rules: Self.baseRules + "p { display: block; } #frame { border: 2px solid black; }"
        )
        page.frame.setNeedsPaint()
        page.frame.paint()
        let iframe: ElementRef = try #require(page.firstElement(id: "frame"))
        let box: Rect = page.tree.selfRect(try #require(page.firstEmbedID(in: iframe)))

        #expect(fills(page).map(\.rect) == sideRects(box, EdgeInsets(top: 2, right: 2, bottom: 2, left: 2)))
        #expect(!page.frame.displayList.contains(where: { $0.name == "outline" }))
    }
}
