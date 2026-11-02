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
        let boxLayout: LayoutRef = try #require(page.firstBlock(in: box))
        let oneLayout: LayoutRef = try #require(page.firstBlock(in: one))
        let twoLayout: LayoutRef = try #require(page.firstBlock(in: two))
        let threeLayout: LayoutRef = try #require(page.firstBlock(in: three))
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
        #expect(boxLayout.children[0].id == oneLayout.id)
        #expect(boxLayout.children[2].id == twoLayout.id)
        #expect(boxLayout.children[3].id == threeLayout.id)

        let inserted: LayoutRef = boxLayout.children[1]
        #expect(inserted.node.element?.tag == "p")
        #expect(inserted.previous?.id == oneLayout.id)
        #expect(twoLayout.previous?.id == inserted.id)
        #expect(threeLayout.previous?.id == twoLayout.id)
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
