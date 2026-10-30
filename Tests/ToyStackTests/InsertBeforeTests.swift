import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct InsertBeforeTests {

    private let css: String = """
        body { display: block; }
        div { display: block; }
        p { display: block; height: 20px; }
    """

    @Test func insertKeepsExistingLayoutChildren() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p id="one">one</p><p id="two">two</p><p id="three">three</p></div>"#,
            rules: css
        )
        let box: Element = try #require(page.firstElement(id: "box"))
        let one: Element = try #require(page.firstElement(id: "one"))
        let two: Element = try #require(page.firstElement(id: "two"))
        let three: Element = try #require(page.firstElement(id: "three"))
        let boxLayout: BlockLayout = try #require(box.layoutObject as? BlockLayout)
        let oneLayout: BlockLayout = try #require(one.layoutObject as? BlockLayout)
        let twoLayout: BlockLayout = try #require(two.layoutObject as? BlockLayout)
        let threeLayout: BlockLayout = try #require(three.layoutObject as? BlockLayout)
        let twoYBefore: CGFloat = twoLayout.y
        page.frame.js = JSRuntime(frame: page.frame)

        page.frame.js.run(
            script: "insertBefore",
            code: """
                var box = document.getElementById('box');
                var fresh = document.createElement('p');
                fresh.textContent = 'inserted';
                box.insertBefore(fresh, document.getElementById('two'));
            """)
        page.frame.rules = CSSParser(css).parse().rules

        profiler.reset()
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(box.children.count == 4)
        #expect(boxLayout.children.count == 4)
        #expect(boxLayout.children[0] === oneLayout)
        #expect(boxLayout.children[2] === twoLayout)
        #expect(boxLayout.children[3] === threeLayout)

        let inserted: BlockLayout = try #require(boxLayout.children[1] as? BlockLayout)
        #expect((inserted.node as? Element)?.tag == "p")
        #expect(inserted.previous === oneLayout)
        #expect(twoLayout.previous === inserted)
        #expect(threeLayout.previous === twoLayout)
        #expect(twoLayout.y > twoYBefore)
        #expect(profiler.snapshot()["layout.children.rebuilt"] == nil)
        #expect((profiler.snapshot()["layout.children.inserted"]?.count ?? 0) == 1)
        expectIncrementalMatchesFull(page)
    }

    @Test func sameParentMoveRebuildsOnlyThatParent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p id="one">one</p><p id="two">two</p><p id="three">three</p></div>"#,
            rules: css
        )
        let box: Element = try #require(page.firstElement(id: "box"))
        page.frame.js = JSRuntime(frame: page.frame)

        page.frame.js.run(
            script: "insertBefore",
            code: """
                var box = document.getElementById('box');
                box.insertBefore(
                    document.getElementById('three'),
                    document.getElementById('one')
                );
            """
        )
        page.frame.rules = CSSParser(css).parse().rules

        profiler.reset()
        page.frame.setNeedsRender()
        page.frame.render()

        let ids: [String?] = box.children.map { ($0 as? Element)?.attributes["id"] }
        #expect(ids == ["three", "one", "two"])
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 1)
        expectIncrementalMatchesFull(page)
    }
}
