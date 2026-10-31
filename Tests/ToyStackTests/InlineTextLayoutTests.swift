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
        let p: Element = try #require(page.firstElement(tag: "p"))
        let beforeWidth: CGFloat = page.textWidth(in: p)
        let beforeHeight: CGFloat = try #require(page.lines(in: p).first).height

        p.attributes["style"] = "font-size: 32px;"
        page.frame.setNeedsRender()
        page.frame.render()

        let afterWidth: CGFloat = page.textWidth(in: p)
        let afterHeight: CGFloat = try #require(page.lines(in: p).first).height
        #expect(afterWidth > beforeWidth)
        #expect(afterHeight > beforeHeight)
    }

    @Test func nowrapKeepsWrappingWordsOnOneLine() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>one two three four five six seven eight</p>"#,
            rules: textPageRules
        )
        let p: Element = try #require(page.firstElement(tag: "p"))
        let linesBefore: Int = page.lines(in: p).count
        #expect(linesBefore > 1)

        p.attributes["style"] = "white-space: nowrap"
        page.frame.setNeedsRender()
        page.frame.render()

        let linesAfter: Int = page.lines(in: p).count
        #expect(linesAfter == 1)
    }

    @Test func fontSizeChangeRebuildsInlineItems() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>one two three four five</p>"#,
            rules: textPageRules
        )
        let p: Element = try #require(page.firstElement(tag: "p"))

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
        let p: Element = try #require(page.firstElement(tag: "p"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)

        let before: [ObjectIdentifier] = treeToList(block)
            .compactMap({ $0 as? TextLayout })
            .map { ObjectIdentifier($0) }

        page.frame.frameWidth = 300
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(treeToList(block).compactMap { $0 as? TextLayout }.map { ObjectIdentifier($0) } == before)

        let text: TextNode = try #require(p.children.first as? TextNode)
        text.append(" six")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((profiler.snapshot()["layout.inline.refresh"]?.count ?? 0) > 0)
        expectIncrementalMatchesFull(page)
    }
}
