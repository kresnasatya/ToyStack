import CoreGraphics
import Testing

@testable import Engine

private let textPageRules: String = """
    html { width: 400px; }
    body { display: block; }
    p { display: block; width: 100px; }
    """

@Suite(.serialized)
@MainActor
struct InlineTextLayoutTests {

    @Test func fontSizeChangeReflowsTextAndLineHeight() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>one two three four five</p>"#,
            rules: textPageRules
        )
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let beforeWidth: CGFloat = page.textWidthID(in: p)
        let beforeLine: LayoutID = try #require(page.lineIDs(in: p).first)
        let beforeHeight: CGFloat = page.tree.height(beforeLine)

        p.attributes["style"] = "font-size: 32px;"
        page.frame.setNeedsRender()
        page.frame.render()

        let afterWidth: CGFloat = page.textWidthID(in: p)
        let afterLine: LayoutID = try #require(page.lineIDs(in: p).first)
        let afterHeight: CGFloat = page.tree.height(afterLine)
        #expect(afterWidth > beforeWidth)
        #expect(afterHeight > beforeHeight)
    }

    @Test func nowrapKeepsWrappingWordsOnOneLine() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>one two three four five six seven eight</p>"#,
            rules: textPageRules
        )
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let linesBefore: Int = page.lineIDs(in: p).count
        #expect(linesBefore > 1)

        p.attributes["style"] = "white-space: nowrap"
        page.frame.setNeedsRender()
        page.frame.render()

        let linesAfter: Int = page.lineIDs(in: p).count
        #expect(linesAfter == 1)
    }

    @Test func fontSizeChangeRebuildsInlineItems() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>one two three four five</p>"#,
            rules: textPageRules
        )
        let p: ElementRef = try #require(page.firstElement(tag: "p"))

        p.attributes["style"] = "font-size: 32px;"
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((profiler.snapshot()["layout.inline.refresh"]?.count ?? 0) > 0)
    }

    @Test func widthChangeKeepsTextObjectsButTextChangeReplacesThem() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five</p>"#,
            rules: textPageRules
        )
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))

        let before: [LayoutID] = treeToList(page.tree, block)
            .filter({ page.tree.isText($0) })

        page.frame.setViewport(width: 300, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(treeToList(page.tree, block).filter { page.tree.isText($0) } == before)

        let text: TextRef = try #require(p.children.first?.text)
        text.append(" six")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((profiler.snapshot()["layout.inline.refresh"]?.count ?? 0) > 0)
        expectIncrementalMatchesFull(page)
    }
}
