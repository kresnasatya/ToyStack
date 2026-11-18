import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct SelectionPaintTests {
    private static let rules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        """

    private func highlights(_ page: LayoutTestPage) -> [Rect] {
        return page.frame.displayList.compactMap { op in
            guard case .rect(let rect, let color) = op, color == selectionHighlightColor else { return nil }
            return rect
        }
    }

    private func press(_ page: LayoutTestPage, _ point: CGPoint, clickCount: Int = 1) {
        page.frame.pressText(x: point.x, y: point.y, clickCount: clickCount)
    }

    @Test func selectedWordPaintsAHighlightBehindItsText() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p>", rules: Self.rules)
        let start: CGPoint = page.textPoint("world", offset: 0)
        let end: CGPoint = page.textPoint("world", offset: 5)

        press(page, start, clickCount: 2)
        page.frame.paint()

        let highlight: Rect = try #require(highlights(page).first)
        #expect(highlights(page).count == 1)
        #expect(abs(highlight.left - start.x) < 1)
        #expect(abs(highlight.right - end.x) < 1)
        #expect(highlight.containsPoint(start.x + 1, start.y))
        let ops: [DisplayOp] = page.frame.displayList
        let highlightIndex: Int = try #require(ops.firstIndex(where: { op in
            guard case .rect(_, let color) = op else { return false }
            return color == selectionHighlightColor
        }))
        let textIndex: Int = try #require(ops.firstIndex(where: { op in
            guard case .text(let text, _, _, _) = op else { return false }
            return text.contains("world")
        }))
        #expect(highlightIndex < textIndex)
    }

    @Test func highlightCoversTheSpaceBetweenSelectedWords() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p>", rules: Self.rules)
        let helloEnd: CGPoint = page.textPoint("hello", offset: 5)
        let worldStart: CGPoint = page.textPoint("world", offset: 0)

        press(page, page.textPoint("hello", offset: 0))
        page.frame.dragText(x: worldStart.x + 1, y: worldStart.y)
        page.frame.dragText(x: page.textPoint("world", offset: 5).x, y: worldStart.y)
        page.frame.paint()

        let space: CGFloat = (helloEnd.x + worldStart.x) / 2
        #expect(highlights(page).contains(where: { $0.containsPoint(space, helloEnd.y) }))
    }

    @Test func selectionShowsOnALineThatWasAlreadyPaintedAndLeavesWithIt() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p><p>other line</p>", rules: Self.rules)
        page.frame.paint()
        try #require(highlights(page).isEmpty)

        press(page, page.textPoint("world", offset: 2), clickCount: 2)
        page.frame.paint()
        try #require(highlights(page).count == 1)

        press(page, page.textPoint("other", offset: 1))
        page.frame.paint()

        #expect(highlights(page).isEmpty)
    }

    @Test func aCollapsedSelectionPaintsNothing() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>hello world</p>", rules: Self.rules)

        press(page, page.textPoint("world", offset: 2))
        page.frame.paint()

        #expect(highlights(page).isEmpty)
    }

    @Test func lineThatPaintsFromInlineBoxesStillShowsTheHighlight() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>alpha beta gamma delta</p>", rules: Self.rules)
        page.frame.setStyleRules(CSSParser(Self.rules + "html { width: 90px; }").parse().rules)
        page.frame.setNeedsRender()
        page.frame.render()
        let lines: [LayoutID] = page.lineIDs(in: try #require(page.firstElement(tag: "p")))
        try #require(lines.contains(where: { line in
            page.tree.currentInlineBoxes(line) != nil && !page.tree.childrenIDs(of: line).contains(where: { page.tree.isText($0) })
        }))
        let start: CGPoint = page.textPoint("gamma", offset: 0)
        let end: CGPoint = page.textPoint("gamma", offset: 5)

        press(page, page.textPoint("gamma", offset: 2), clickCount: 2)
        page.frame.paint()

        let highlight: Rect = try #require(highlights(page).first)
        #expect(highlights(page).count == 1)
        #expect(abs(highlight.left - start.x) < 1)
        #expect(abs(highlight.right - end.x) < 1)
        #expect(highlight.containsPoint(start.x + 1, start.y))
    }
}
