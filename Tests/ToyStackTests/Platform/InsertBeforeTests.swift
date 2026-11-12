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
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let one: ElementRef = try #require(page.firstElement(id: "one"))
        let two: ElementRef = try #require(page.firstElement(id: "two"))
        let three: ElementRef = try #require(page.firstElement(id: "three"))
        let boxLayout: LayoutID = try #require(page.firstBlockID(in: box))
        let oneLayout: LayoutID = try #require(page.firstBlockID(in: one))
        let twoLayout: LayoutID = try #require(page.firstBlockID(in: two))
        let threeLayout: LayoutID = try #require(page.firstBlockID(in: three))
        let twoYBefore: CGFloat = page.tree.y(twoLayout)
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(
            script: "insertBefore",
            code: """
                var box = document.getElementById('box');
                var fresh = document.createElement('p');
                fresh.textContent = 'inserted';
                box.insertBefore(fresh, document.getElementById('two'));
            """)
        page.frame.setStyleRules(CSSParser(css).parse().rules)

        profiler.reset()
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(box.children.count == 4)
        let children: [LayoutID] = page.tree.childrenIDs(of: boxLayout)
        #expect(children.count == 4)
        #expect(children[0] == oneLayout)
        #expect(children[2] == twoLayout)
        #expect(children[3] == threeLayout)

        let inserted: LayoutID = children[1]
        #expect(page.tree.domRef(inserted).element?.tag == "p")
        #expect(page.tree.previousID(of: inserted) == oneLayout)
        #expect(page.tree.previousID(of: twoLayout) == inserted)
        #expect(page.tree.previousID(of: threeLayout) == twoLayout)
        #expect(page.tree.y(twoLayout) > twoYBefore)
        #expect(profiler.snapshot()["layout.children.rebuilt"] == nil)
        #expect((profiler.snapshot()["layout.children.inserted"]?.count ?? 0) == 1)
        expectIncrementalMatchesFull(page)
    }

    @Test func sameParentMoveRebuildsOnlyThatParent() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p id="one">one</p><p id="two">two</p><p id="three">three</p></div>"#,
            rules: css
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

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
        page.frame.setStyleRules(CSSParser(css).parse().rules)

        profiler.reset()
        page.frame.setNeedsRender()
        page.frame.render()

        let ids: [String?] = box.children.map { $0.element?.attributes["id"] }
        #expect(ids == ["three", "one", "two"])
        #expect((profiler.snapshot()["layout.children.rebuilt"]?.count ?? 0) == 1)
        expectIncrementalMatchesFull(page)
    }
}
