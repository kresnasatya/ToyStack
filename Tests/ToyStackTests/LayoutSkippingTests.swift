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
        let bodyBefore: BlockLayout = try #require(
            page.firstElement(tag: "body")?.layoutObject as? BlockLayout
        )
        let childrenBefore: [ObjectIdentifier] = bodyBefore.children.map {
            ObjectIdentifier($0 as AnyObject)
        }

        page.frame.setNeedsLayout()
        page.frame.render()

        let bodyAfter: BlockLayout = try #require(
            page.firstElement(tag: "body")?.layoutObject as? BlockLayout
        )
        #expect(bodyAfter === bodyBefore)
        #expect(bodyAfter.children.map { ObjectIdentifier($0 as AnyObject) } == childrenBefore)
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
        let document: DocumentLayout = try #require(page.frame.document)
        let leaf: Element = try #require(
            treeToList(page.frame.nodes)
                .compactMap({ $0 as? Element })
                .first(where: { $0.attributes["id"] == "leaf" })
        )
        let body: BlockLayout = try #require(
            page.firstElement(tag: "body")?.layoutObject as? BlockLayout
        )
        let totalBlocks: Int = treeToList(document)
            .compactMap({ $0 as? BlockLayout })
            .count
        let cleanSiblingsBefore: [ObjectIdentifier] = body.children.dropFirst().map {
            ObjectIdentifier($0 as AnyObject)
        }
        #expect(totalBlocks == 13)

        InlineStyle.set(leaf, property: "width", value: "123px")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 4)
        #expect((profiler.snapshot()["layout.skipped"]?.count ?? 0) == 9)
        #expect(
            body.children.dropFirst().map { ObjectIdentifier($0 as AnyObject) }
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
        let p: Element = try #require(page.firstElement(tag: "p"))
        let block: BlockLayout = try #require(p.layoutObject as? BlockLayout)
        let line: LineLayout = try #require(block.children.first as? LineLayout)
        let text: TextLayout = try #require(
            treeToList(line).compactMap({ $0 as? TextLayout }).last
        )
        #expect(text.x + text.textWidth == block.x + block.width)

        text.fontField.mark()
        profiler.reset()
        line.layout()

        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) > 0)
        #expect((profiler.snapshot()["layout.text"]?.count ?? 0) > 0)
        #expect(text.x + text.textWidth == block.x + block.width)

        profiler.reset()
        line.layout()
        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) == 0)
    }
}
