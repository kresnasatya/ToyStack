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
        let bodyBefore: LayoutID = try #require(page.firstBlockID(in: bodyElement))
        let childrenBefore: [LayoutID] = page.tree.childrenIDs(of: bodyBefore)

        page.frame.setNeedsLayout()
        page.frame.render()

        let bodyAfter: LayoutID = try #require(page.firstBlockID(in: bodyElement))
        #expect(bodyAfter == bodyBefore)
        #expect(page.tree.childrenIDs(of: bodyAfter) == childrenBefore)
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
        let document: LayoutTree = page.tree
        let leaf: ElementRef = try #require(
            treeToList(page.frame.nodes)
                .compactMap({ $0.element })
                .first(where: { $0.attributes["id"] == "leaf" })
        )
        let bodyElement: ElementRef = try #require(page.firstElement(tag: "body"))
        let body: LayoutID = try #require(page.firstBlockID(in: bodyElement))
        let totalBlocks: Int = treeToList(document, document.rootID)
            .filter({ document.isBlock($0) })
            .count
        let cleanSiblingsBefore: [LayoutID] = Array(
            document.childrenIDs(of: body).dropFirst()
        )
        #expect(totalBlocks == 13)

        InlineStyle.set(leaf, property: "width", value: "123px")
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((profiler.snapshot()["layout.visited"]?.count ?? 0) == 4)
        #expect((profiler.snapshot()["layout.skipped"]?.count ?? 0) == 9)
        #expect(
            Array(page.tree.childrenIDs(of: body).dropFirst())
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
        let block: LayoutID = try #require(page.firstBlockID(in: p))
        let line: LayoutID = try #require(page.firstLineID(in: p))
        let tree: LayoutTree = page.tree
        let text: LayoutID = try #require(
            treeToList(tree, line).last(where: { tree.isText($0) })
        )
        #expect(
            tree.x(text) + tree.textData(text).metrics.width
                == tree.x(block) + tree.width(block)
        )

        tree.markField(.font, at: text)
        profiler.reset()
        tree.layout(line)

        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) > 0)
        #expect((profiler.snapshot()["layout.text"]?.count ?? 0) > 0)
        #expect(
            tree.x(text) + tree.textData(text).metrics.width
                == tree.x(block) + tree.width(block)
        )

        profiler.reset()
        tree.layout(line)
        #expect((profiler.snapshot()["layout.line.place"]?.count ?? 0) == 0)
    }
}
