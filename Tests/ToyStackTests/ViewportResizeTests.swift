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
        page.frame.setScroll(tallMax)

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
        page.frame.setScroll(page.frame.maxScroll)
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
        let p: ElementRef = try #require(page.firstElement(id: "para"))

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let block: LayoutID = try #require(page.firstBlockID(in: p))
        #expect(page.tree.width(block) == CGFloat(400) - 2 * HSTEP)
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
        let cardElement: ElementRef = try #require(page.firstElement(id: "card"))
        let card: LayoutID = try #require(page.firstBlockID(in: cardElement))
        let childrenBefore: [LayoutID] = page.tree.childrenIDs(of: card)

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let cardAfter: LayoutID = try #require(page.firstBlockID(in: cardElement))
        #expect(cardAfter == card)
        #expect(page.tree.childrenIDs(of: card) == childrenBefore)
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
        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
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

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
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
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))

        let linesBefore: [LayoutID] = page.tree.childrenIDs(of: block)
        let textsBefore: [LayoutID] = treeToList(page.tree, block).filter({ page.tree.isText($0) })

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        #expect(page.tree.childrenIDs(of: block) == linesBefore)
        #expect(treeToList(page.tree, block).filter({ page.tree.isText($0) }) == textsBefore)
        #expect((profiler.snapshot()["layout.inline.place"]?.count ?? 0) == 0)
        expectIncrementalMatchesFull(page)
    }

    @Test func widthResizeWithBreakChangeFragmentsTextPerLine() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five six seven eight nine ten</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))

        page.frame.setViewport(width: 300, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let lines: [LayoutID] = page.tree.childrenIDs(of: block)
            .filter({ page.tree.isLine($0) })
        #expect(!lines.isEmpty)
        for line in lines {
            let fragments: [InlineBox] = page.tree[line: line].content.boxes
            #expect(fragments.count == 1)
        }
        expectIncrementalMatchesFull(page)
    }

    @Test func widthResizeWithBreakChangeReusesLineObjects() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two three four five six seven eight nine ten</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        let linesBefore: [LayoutID] = page.tree.childrenIDs(of: block)
            .filter({ page.tree.isLine($0) })

        page.frame.setViewport(width: 300, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        page.frame.render()

        let linesAfter: [LayoutID] = page.tree.childrenIDs(of: block)
            .filter({ page.tree.isLine($0) })
        let reused: Int = min(linesBefore.count, linesAfter.count)

        #expect(Array(linesAfter.prefix(reused)) == Array(linesBefore.prefix(reused)))
        expectIncrementalMatchesFull(page)
    }

    @Test func widthResizeReusesUnchangedLinePrefix() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p id="para">one two<br>three four five six seven eight nine ten</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
                """
        )
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        let firstLine: LayoutID = try #require(
            page.tree.childrenIDs(of: block).first(where: { page.tree.isLine($0) })
        )

        page.frame.setViewport(width: 220, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let linesAfter: [LayoutID] = page.tree.childrenIDs(of: block)
            .filter({ page.tree.isLine($0) })
        let metrics: [String: ProfileMetric] = profiler.snapshot()
        #expect(linesAfter.first == firstLine)
        #expect((metrics["layout.inline.place.reusedLines"]?.count ?? 0) > 0)
        #expect((metrics["layout.inline.place.rebuiltLines"]?.count ?? 0) > 0)
        #expect((metrics["layout.line.place.verticalOnly"]?.count ?? 0) > 0)
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
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        #expect(page.tree.childrenIDs(of: block).count == 2)

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let profile = profiler.snapshot()
        #expect((profile["layout.line.place.skipped"]?.count ?? 0) > 0)
        #expect((profile["layout.line.place.placed"]?.count ?? 0) == 0)
        #expect((profile["layout.sweep.skipped"]?.count ?? 0) == 1)
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
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        let lines: [LayoutID] = page.tree.childrenIDs(of: block).filter({ page.tree.isLine($0) })
        #expect(lines.count == 2)
        page.withTree { tree in
            for line in lines {
                tree[line: line].content.centered = true
            }
        }

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
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
        let p: ElementRef = try #require(page.firstElement(id: "para"))
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        #expect(page.tree.childrenIDs(of: block).count == 2)

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
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
        let image: ElementRef = try #require(page.firstElement(id: "photo"))
        image.image = makeTestImage(width: 200, height: 100)
        LayoutInvalidation.imageChanged(page.ref(of: image))
        page.frame.setNeedsRender()
        page.frame.render()

        let before: LayoutID = try #require(page.firstEmbedID(in: image))
        let beforeWidth: CGFloat = page.tree.width(before)

        page.frame.setViewport(width: 300, height: page.frame.frameHeight)
        page.frame.setNeedsViewportResize()
        profiler.reset()
        page.frame.render()

        let after: LayoutID = try #require(page.firstEmbedID(in: image))
        #expect(page.tree.width(after) < beforeWidth)
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

        page.frame.setViewport(width: 400, height: page.frame.frameHeight)
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
        let p: ElementRef = try #require(page.firstElement(id: "para"))

        InlineStyle.set(p, property: "width", value: "200px")
        page.frame.setNeedsRender()
        profiler.reset()
        page.frame.render()

        let changed = profiler.snapshot()
        #expect((changed["layout.block.style.cache.miss"]?.count ?? 0) > 0)

        page.frame.setViewport(width: 350, height: page.frame.frameHeight)
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
