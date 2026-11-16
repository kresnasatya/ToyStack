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

    private func shrunk(_ rect: Rect, by amount: CGFloat) -> Rect {
        return Rect(
            left: rect.left + amount,
            top: rect.top + amount,
            right: rect.right - amount,
            bottom: rect.bottom - amount
        )
    }

    @Test func borderIsDrawnInsideTheBorderBox() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"></div>"#,
            rules: Self.baseRules + "#box { padding: 6px; border: 4px solid red; }"
        )
        let box: Rect = try paintedBox(page, id: "box")

        let strokes: [(rect: Rect, width: CGFloat)] = page.frame.displayList.compactMap { op in
            guard case .outline(let rect, _, let width) = op else { return nil }
            return (rect, width)
        }
        #expect(strokes.count == 1)
        #expect(strokes.first?.rect == shrunk(box, by: 2))
        #expect(strokes.first?.width == 4)
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

        let fills: [Rect] = page.frame.displayList.compactMap { op in
            guard case .rect(let rect, _) = op else { return nil }
            return rect
        }
        #expect(fills.contains(borderBox))
    }

    @Test func overflowHiddenClipsInsideTheBorder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><div></div></div>"#,
            rules: Self.baseRules + "#box { overflow: hidden; border: 5px solid red; }"
        )
        let box: Rect = try paintedBox(page, id: "box")

        let clips: [Rect] = page.frame.displayList.compactMap { op in
            guard case .beginEffect(let scope) = op, case .clip(let shape) = scope.kind else {
                return nil
            }
            return shape.rect
        }
        #expect(clips == [shrunk(box, by: 5)])
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
        #expect(scrollports == [shrunk(box, by: 5)])
    }
}
