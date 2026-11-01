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

    @Test func widthOnlyResizeSkipsLinePlacementWhenPlanUnchanged() throws {
        // <br> keeps the line plan deterministic. The paragraph is
        // multi-line and left-aligned, so a width-only change must not
        // reposition children.
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three<br>four five six</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(id: "para"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        #expect(block.children.count == 2)

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let profile = profiler.snapshot()
        #expect((profile["layout.line.place.skipped"]?.count ?? 0) > 0)
        #expect((profile["layout.line.place.placed"]?.count ?? 0) == 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func centeredLineStillPlacesOnWidthChange() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three<br>four five six</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(id: "para"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        let lines: [LineLayout] = block.children.compactMap({ $0 as? LineLayout })
        #expect(lines.count == 2)
        for line in lines {
            line.centered = true
        }

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let profile = profiler.snapshot()
        #expect((profile["layout.line.place.placed"]?.count ?? 0) > 0)
    }

    @Test func rtlLineStillPlacesOnWidthChange() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para" dir="rtl">one two three<br>four five six</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(id: "para"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        #expect(block.children.count == 2)

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let profile = profiler.snapshot()
        #expect((profile["layout.line.place.placed"]?.count ?? 0) > 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func percentWidthImageStillPlacesOnWidthChange() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">before <img id="photo"> after</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
                img { max-width: 50%; }
            """
        )
        let image: Element = try #require(page.firstElement(id: "photo"))
        image.image = makeTestImage(width: 200, height: 100)
        LayoutInvalidation.imageChanged(image)
        page.frame.setNeedsRender()
        page.frame.render()

        let before: ImageLayout = try #require(page.firstLayout(ImageLayout.self, in: image))
        let beforeWidth: CGFloat = before.width

        page.frame.frameWidth = 300
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let after: ImageLayout = try #require(page.firstLayout(ImageLayout.self, in: image))
        #expect(after.width < beforeWidth)
        #expect((profiler.snapshot()["layout.line.place.placed"]?.count ?? 0) > 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func widthResizeHitsBlockStyleCache() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five six seven eight</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )

        page.frame.frameWidth = 400
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let profile = profiler.snapshot()
        #expect((profile["layout.block.style.cache.hit"]?.count ?? 0) > 0)
        #expect((profile["layout.block.style.cache.miss"]?.count ?? 0) == 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func styleChangeMissesThenNextResizeHits() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five six seven eight</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: Element = try #require(page.firstElement(id: "para"))

        InlineStyle.set(p, property: "width", value: "200px")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        let changed = profiler.snapshot()
        #expect((changed["layout.block.style.cache.miss"]?.count ?? 0) > 0)

        page.frame.frameWidth = 350
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let resized = profiler.snapshot()
        #expect((resized["layout.block.style.cache.miss"]?.count ?? 0) == 0)
        #expect((resized["layout.block.style.cache.hit"]?.count ?? 0) > 0)
        expectIncrementalMatchesFull(page)
    }
}

private func makeTestImage(width: Int, height: Int) -> CGImage {
    let context: CGContext = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
