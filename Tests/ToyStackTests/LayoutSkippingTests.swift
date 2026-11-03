import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutSkippingTests {

    @Test func cleanSecondLayoutVisitsNoBlocks() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div>one</div><div>two</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                """
        )
        let bodyElement: ElementRef = try #require(page.firstElement(tag: "body"))
        let bodyBefore: LayoutRef = try #require(page.firstBlock(in: bodyElement))
        let childrenBefore: [LayoutID] = bodyBefore.children.map { $0.id }

        page.frame.setNeedsLayout()
        page.frame.render()

        let bodyAfter: LayoutRef = try #require(page.firstBlock(in: bodyElement))
        #expect(bodyAfter.id == bodyBefore.id)
        #expect(bodyAfter.children.map { $0.id } == childrenBefore)
        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 0)
        #expect((profiler.snapshot()["layout.skipped"]?.count ?? 0) == 0)
    }

    @Test func dirtyLeafVisitsOnlyItsBlockPath() throws {
        // Keep this on one line: whitespace between block tags creates anonymous
        // BlockLayouts and changes the expected visit count.
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="first"><div id="leaf">x</div></div><div>1</div><div>2</div><div>3</div><div>4</div><div>5</div><div>6</div><div>7</div><div>8</div><div>9</div>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; height: 10px; }
                """
        )
        let document: LayoutTree = try #require(page.frame.document)
        let leaf: ElementRef = try #require(
            treeToList(page.frame.nodes)
                .compactMap({ $0.element })
                .first(where: { $0.attributes["id"] == "leaf" })
        )
        let bodyElement: ElementRef = try #require(page.firstElement(tag: "body"))
        let body: LayoutRef = try #require(page.firstBlock(in: bodyElement))
        let totalBlocks: Int = treeToList(document.root)
            .filter({ $0.isBlock })
            .count
        let cleanSiblingsBefore: [LayoutID] = body.children.dropFirst().map {
            $0.id
        }
        #expect(totalBlocks == 13)

        InlineStyle.set(leaf, property: "width", value: "123px")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 4)
        #expect((profiler.snapshot()["layout.skipped"]?.count ?? 0) == 9)
        #expect(
            body.children.dropFirst().map { $0.id }
                == cleanSiblingsBefore
        )
    }

    @Test func lineRunsWhenChildFieldIsDirty() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p dir="rtl">abc def</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                p { display: block; width: 300px; }
                """
        )
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutRef = try #require(page.firstBlock(in: p))
        let line: LayoutRef = try #require(page.firstLine(in: p))
        let text: LayoutRef = try #require(
            treeToList(line).last(where: { $0.isText })
        )
        #expect(text.x + text.textData.metrics.width == block.x + block.width)

        text.tree.markField(.font, at: text.id)
        profiler.reset()
        line.layout()

        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) > 0)
        #expect((profiler.snapshot()["layout.text"]?.count ?? 0) > 0)
        #expect(text.x + text.textData.metrics.width == block.x + block.width)

        profiler.reset()
        line.layout()
        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) == 0)
    }
}
