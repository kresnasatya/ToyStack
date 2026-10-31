import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ViewportResizeTests {

    @Test func verticalResizeDoesNoBlockWorkAndClampsScroll() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="tall" style="height: 1200px">text</div>"#,
            rules: """
                body { display: block; }
                div { display: block; }
            """
        )
        let tallMax: CGFloat = page.frame.maxScroll
        page.frame.scroll = tallMax

        page.tab.resize(width: 800, height: 900)
        page.frame.render()
        page.frame.commitFrame()

        #expect(page.frame.scroll == page.frame.maxScroll)
        #expect(page.frame.maxScroll < tallMax)
        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 0)
        #expect((profiler.snapshot()["layout.skipped"]?.count ?? 0) == 1)
    }

    @Test func wideningAtBottomClampsAfterLayout() throws {
        let words: String = Array(repeating: "word", count: 40).joined(separator: " ")
        let rows: String = (0..<200).map({ "<p>row \($0) \(words)</p>" }).joined()
        let page: LayoutTestPage = LayoutTestPage(
            html: "<div>\(rows)</div>",
            rules: """
                body { display: block; }
                div { display: block; }
                p { display: block; }
            """
        )
        page.frame.paint()
        page.frame.scroll = page.frame.maxScroll
        let tallMax: CGFloat = page.frame.maxScroll

        page.tab.resize(width: 1200, height: 600)
        page.frame.render()
        page.frame.paint()
        page.frame.commitFrame()

        #expect(page.frame.maxScroll < tallMax)
        #expect(page.frame.scroll == page.frame.maxScroll)
    }

    @Test func horizontalResizeRebuildsAutoWidthBlocks() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(id: "para"))

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        #expect(block.width == CGFloat(400) - 2 * HSTEP)
        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) > 0)
        #expect((profiler.snapshot()["layout.inline.place"]?.count ?? 0) > 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func horizontalResizeSkipsFixedWidthSubtree() throws {
        let rows: String = (0..<20).map({ "<p>row \($0)</p>" }).joined(separator: "\n ")
        let page: LayoutTestPage = LayoutTestPage(
            html: "<div id=\"card\">\n \(rows)\n</div>",
            rules: """
                body { display: block; }
                div { display: block; width: 200px; }
                p { display: block; }
            """
        )
        let card: BlockLayout = try #require(page.firstElement(id: "card")?.layoutObject as? BlockLayout)
        let childrenBefore: [ObjectIdentifier] = card.children.map {
            ObjectIdentifier($0 as AnyObject)
        }

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let cardAfter: BlockLayout = try #require(page.firstElement(id: "card")?.layoutObject as? BlockLayout)
        #expect(cardAfter === card)
        #expect(card.children.map { ObjectIdentifier($0 as AnyObject) } == childrenBefore)
        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) < 10)
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func horizontalResizeReflowsMixedInlineContent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="mix">alpha beta <p>block words here</p> gamma delta epsilon</div>"#,
            rules: """
                body { display: block; }
                div { display: block; }
                p { display: block; }
            """
        )
        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        page.frame.render()
        expectIncrementalMatchesFull(page)
    }

    @Test func horizontalResizeReusesInlineItems() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let profile = profiler.snapshot()
        #expect((profile["layout.inline.refresh"]?.count ?? 0) == 0)
        #expect((profile["text.words"]?.count ?? 0) == 0)
        #expect((profile["layout.inline.place"]?.count ?? 0) > 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func widthResizeWithoutBreakChangeKeepsInlineTree() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para" style="white-space: nowrap;">one two three four</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(id: "para"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)

        let linesBefore: [ObjectIdentifier] = block.children.map { ObjectIdentifier($0 as AnyObject) }
        let textsBefore: [ObjectIdentifier] = treeToList(block)
            .compactMap({ $0 as? TextLayout })
            .map({ ObjectIdentifier($0) })

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(block.children.map { ObjectIdentifier($0 as AnyObject) } == linesBefore)
        #expect(treeToList(block).compactMap({ $0 as? TextLayout }).map { ObjectIdentifier($0) } == textsBefore)
        #expect((profiler.snapshot()["layout.inline.place"]?.count ?? 0) == 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func widthResizeWithBreakChangeReusesTextObjects() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five six seven eight nine ten</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(id: "para"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)

        let textsBefore: [ObjectIdentifier] = treeToList(block)
            .compactMap({ $0 as? TextLayout })
            .map { ObjectIdentifier($0) }

        page.frame.frameWidth = 300
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(treeToList(block).compactMap { $0 as? TextLayout }.map { ObjectIdentifier($0) } == textsBefore)
        expectIncrementalMatchesFull(page)
    }
}
