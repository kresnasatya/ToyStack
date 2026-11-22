import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct TextSelectionTests {
    private static let rules: String = """
        html { width: 600px; }
        body { display: block; }
        p { display: block; }
        """

    private func screen(_ page: LayoutTestPage, _ point: CGPoint) -> CGPoint {
        let zoom: CGFloat = page.tab.pageZoom
        return CGPoint(x: point.x * zoom, y: (point.y - page.frame.scroll) * zoom)
    }

    private func press(_ page: LayoutTestPage, _ point: CGPoint, clickCount: Int = 1) {
        let at: CGPoint = screen(page, point)
        page.tab.pressText(x: at.x, y: at.y, clickCount: clickCount)
    }

    private func drag(_ page: LayoutTestPage, _ point: CGPoint) {
        let at: CGPoint = screen(page, point)
        page.tab.dragText(x: at.x, y: at.y)
    }

    @Test func draggingAcrossWordsSelectsThem() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)

        press(page, page.textPoint("hello", offset: 0))
        drag(page, page.textPoint("world", offset: 5))

        #expect(page.tab.selectedText == "hello world")
    }

    @Test func draggingBackwardsSelectsTheSameText() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)

        press(page, page.textPoint("world", offset: 5))
        drag(page, page.textPoint("hello", offset: 0))

        #expect(page.tab.selectedText == "hello world")
    }

    @Test func aPressWithoutDraggingSelectsNothing() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)

        press(page, page.textPoint("hello", offset: 2))
        page.tab.releaseText()

        #expect(page.tab.selectedText == "")
    }

    @Test func doubleClickSelectsTheWord() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)
        let point: CGPoint = page.textPoint("world", offset: 2)

        press(page, point)
        page.tab.releaseText()
        press(page, point, clickCount: 2)

        #expect(page.tab.selectedText == "world")
    }

    @Test func doubleClickThenDragGrowsByWholeWords() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>one two three four five</p>", rules: Self.rules)

        press(page, page.textPoint("two", offset: 1), clickCount: 2)
        drag(page, page.textPoint("four", offset: 1))

        #expect(page.tab.selectedText == "two three four")
    }

    @Test func doubleClickThenDragBackwardsKeepsTheFirstWord() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>one two three four five</p>", rules: Self.rules)

        press(page, page.textPoint("four", offset: 1), clickCount: 2)
        drag(page, page.textPoint("two", offset: 1))

        #expect(page.tab.selectedText == "two three four")
    }

    @Test func tripleClickSelectsTheParagraph() {
        let page: LayoutTestPage = LayoutTestPage(
            html: "<p>first paragraph</p><p>second paragraph here</p>",
            rules: Self.rules
        )

        press(page, page.textPoint("here", offset: 1), clickCount: 3)

        #expect(page.tab.selectedText == "second paragraph here")
    }

    @Test func aNewPressDropsTheOldSelection() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)
        press(page, page.textPoint("hello", offset: 0))
        drag(page, page.textPoint("world", offset: 5))

        press(page, page.textPoint("now", offset: 1))

        #expect(page.tab.selectedText == "")
    }

    @Test func movesAfterReleaseDoNotGrowTheSelection() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)
        press(page, page.textPoint("hello", offset: 0))
        drag(page, page.textPoint("hello", offset: 5))
        page.tab.releaseText()

        drag(page, page.textPoint("now", offset: 3))

        #expect(page.tab.selectedText == "hello")
    }

    @Test func dragWithoutAPressSelectsNothing() {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)

        drag(page, page.textPoint("now", offset: 3))

        #expect(page.tab.selectedText == "")
    }

    @Test func pressOnAScrolledPageUsesThePageUnderThePointer() {
        let filler: String = String(repeating: "<p>filler</p>", count: 80)
        let page: LayoutTestPage = LayoutTestPage(
            html: filler + "<p>far below the fold</p>",
            rules: Self.rules
        )
        let target: CGPoint = page.textPoint("below", offset: 0)
        page.frame.setScroll(target.y - 100)

        press(page, target)
        drag(page, page.textPoint("fold", offset: 4))

        #expect(page.tab.selectedText == "below the fold")
    }

    @Test func aNewDocumentStartsWithNothingSelected() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)
        press(page, page.textPoint("hello", offset: 0), clickCount: 3)
        try #require(page.tab.selectedText == "say hello world now")

        page.frame.replaceDOM(HTMLParser(body: "<p>say hello world now</p>").parse())
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(page.tab.selectedText == "")
    }

    @Test func changingTheSelectionAsksForAPaint() throws {
        let page: LayoutTestPage = LayoutTestPage(html: "<p>say hello world now</p>", rules: Self.rules)
        page.frame.paint()
        try #require(!page.frame.needsPaint)

        press(page, page.textPoint("hello", offset: 0), clickCount: 2)

        #expect(page.frame.needsPaint)
    }
}
