import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct InlineBoxPaintTests {
    private static let baseRules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        """

    private func paint(_ page: LayoutTestPage) {
        page.frame.setNeedsPaint()
        page.frame.paint()
    }

    private func fills(_ page: LayoutTestPage, _ color: String) -> [Rect] {
        let wanted: BrowserColor = BrowserColor(cssName: color)
        return page.frame.displayList.compactMap { op in
            guard case .rect(let rect, let color) = op, color == wanted else { return nil }
            return rect
        }
    }

    private func absolute(_ page: LayoutTestPage, _ fragment: InlineBoxFragment, on line: LayoutID) -> Rect {
        return fragment.rect.translated(dx: page.tree.x(line), dy: page.tree.y(line))
    }

    private func lines(_ page: LayoutTestPage) throws -> [LayoutID] {
        return page.lineIDs(in: try #require(page.firstElement(tag: "p")))
    }

    @Test func spanBackgroundAndBorderCoverItsBox() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b</span> c</p>"#,
            rules: Self.baseRules + "#s { padding: 4px; border: 2px solid red; background-color: gold; }"
        )
        paint(page)
        let line: LayoutID = try #require(try lines(page).first)
        let fragment: InlineBoxFragment = try #require(page.tree[line: line].inlineBoxes.fragments.first)
        let box: Rect = absolute(page, fragment, on: line)

        #expect(fills(page, "gold") == [box])
        #expect(fills(page, "red") == [
            Rect(left: box.left, top: box.top, right: box.right, bottom: box.top + 2),
            Rect(left: box.right - 2, top: box.top + 2, right: box.right, bottom: box.bottom - 2),
            Rect(left: box.left, top: box.bottom - 2, right: box.right, bottom: box.bottom),
            Rect(left: box.left, top: box.top + 2, right: box.left + 2, bottom: box.bottom - 2),
        ])
    }

    @Test func wrappedSpanDrawsSideBordersOnlyAtItsEnds() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>start <span id="s">one two three four five six seven</span> end</p>"#,
            rules: """
                html { width: 160px; }
                body { display: block; }
                p { display: block; }
                #s { border-left: 3px solid red; border-right: 5px solid blue; }
                """
        )
        paint(page)
        let owned: [(line: LayoutID, fragment: InlineBoxFragment)] = try lines(page).compactMap { line in
            page.tree[line: line].inlineBoxes.fragments.first.map({ (line, $0) })
        }
        let first: Rect = absolute(page, try #require(owned.first?.fragment), on: try #require(owned.first?.line))
        let last: Rect = absolute(page, try #require(owned.last?.fragment), on: try #require(owned.last?.line))

        #expect(owned.count > 1)
        #expect(fills(page, "red") == [Rect(left: first.left, top: first.top, right: first.left + 3, bottom: first.bottom)])
        #expect(fills(page, "blue") == [Rect(left: last.right - 5, top: last.top, right: last.right, bottom: last.bottom)])
    }

    @Test func backgroundOnlySpanPaintsBehindItsText() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <span id="s">b c</span> d</p>"#,
            rules: Self.baseRules + "#s { background-color: gold; }"
        )
        paint(page)
        let span: ElementRef = try #require(page.firstElement(id: "s"))
        let line: LayoutID = try #require(try lines(page).first)
        let texts: [Rect] = page.tree.childrenIDs(of: line)
            .filter({ page.tree.domID(of: $0) == span.children.first?.id })
            .map({ page.tree.selfRect($0) })
        let expected: Rect = try #require(texts.first)

        #expect(texts.count == 1)
        #expect(fills(page, "gold") == [expected])
        let goldIndex: Int = try #require(page.frame.displayList.firstIndex(where: { op in
            if case .rect(_, let color) = op { return color == BrowserColor(cssName: "gold") }
            return false
        }))
        let textIndex: Int = try #require(page.frame.displayList.firstIndex(where: { op in
            if case .text(let text, _, _, _) = op { return text.contains("b") }
            return false
        }))
        #expect(goldIndex < textIndex)
    }

    @Test func changingASpanBackgroundRepaintsIt() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>a <em><span id="s">b</span></em> c</p>"#,
            rules: Self.baseRules
        )
        paint(page)
        let em: ElementRef = try #require(page.firstElement(tag: "em"))

        InlineStyle.set(em, property: "background-color", value: "gold")
        page.frame.setNeedsRender()
        page.frame.render()
        paint(page)

        #expect(fills(page, "gold").count == 1)
    }
}
