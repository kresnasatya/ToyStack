import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct AppendChildTests {

    @Test func movesChildFromOldParent() throws {
        let css: String = """
            body { display: block; }
            div { display: block; }
            p { display: block; height: 20px; }
        """
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="box"><p id="old">old</p></div>
                <div id="old-parent"><p id="one">one</p><p id="two">two</p></div>
            """,
            rules: css
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let oldParent: ElementRef = try #require(page.firstElement(id: "old-parent"))
        let old: NodeID = box.children[0].id
        let one: NodeID = oldParent.children[0].id
        let two: NodeID = oldParent.children[1].id
        page.frame.js = JSRuntime(frame: page.frame)

        let boxHeightBefore: CGFloat = try #require(page.ref(of: box).layout).height
        let oldParentHeightBefore: CGFloat = try #require(page.ref(of: oldParent).layout).height

        page.frame.js.run(script: "appendChild", code: "document.getElementById('box').appendChild(document.getElementById('one'));")

        #expect(box.children.count == 2)
        #expect(box.children[0].id == old)
        #expect(box.children[1].id == one)
        #expect(page.frame.dom.parent(of: old) == box.id)
        #expect(page.frame.dom.parent(of: one) == box.id)
        #expect(oldParent.children.count == 1)
        #expect(oldParent.children[0].id == two)
        #expect(page.frame.dom.parent(of: two) == oldParent.id)

        page.frame.rules = CSSParser(css).parse().rules
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((page.ref(of: box).layout?.height ?? 0) > boxHeightBefore)
        #expect((page.ref(of: oldParent).layout?.height ?? 0) < oldParentHeightBefore)
    }

    @Test func reappendingExistingChildMovesItToTheEnd() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="box"><p id="one">one</p><p id="two">two</p></div>
            """,
            rules: """
                body { display: block; }
                div { display: block; }
                p { display: block; }
            """
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let one: NodeID = box.children[0].id
        let two: NodeID = box.children[1].id
        page.frame.js = JSRuntime(frame: page.frame)

        page.frame.js.run(
            script: "appendChild",
            code: """
                var box = document.getElementById('box');
                box.appendChild(box.children[0]);
            """
        )

        #expect(box.children.count == 2)
        #expect(box.children[0].id == two)
        #expect(box.children[1].id == one)
        #expect(page.frame.dom.parent(of: one) == box.id)
        #expect(page.frame.dom.parent(of: two) == box.id)
    }

    @Test func appendKeepsExistingLayoutChildren() throws {
        let css: String = """
            body { display: block; }
            div { display: block; }
            p { display: block; height: 20px; }
        """
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="box">
                    <p id="one">one</p>
                    <p id="two">two</p>
                </div>
            """,
            rules: css
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let one: ElementRef = try #require(page.firstElement(id: "one"))
        let two: ElementRef = try #require(page.firstElement(id: "two"))
        let boxLayout: LayoutRef = try #require(page.firstBlock(in: box))
        let oneLayout: LayoutRef = try #require(page.firstBlock(in: one))
        let twoLayout: LayoutRef = try #require(page.firstBlock(in: two))
        let beforeChildren: [LayoutID] = boxLayout.children.map({ $0.id })
        #expect(beforeChildren.count == 5)
        page.frame.js = JSRuntime(frame: page.frame)
        page.frame.js.run(
            script: "appendChild",
            code: """
                var box = document.getElementById('box');
                var fresh = document.createElement('p');
                fresh.textContent = 'three';
                box.appendChild(fresh);
            """
        )
        page.frame.rules = CSSParser(css).parse().rules

        profiler.reset()
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(boxLayout.children.count == 6)
        #expect(boxLayout.children[0].id == beforeChildren[0])
        #expect(boxLayout.children[1].id == oneLayout.id)
        #expect(boxLayout.children[2].id == beforeChildren[2])
        #expect(boxLayout.children[3].id == twoLayout.id)
        #expect(boxLayout.children[4].id == beforeChildren[4])

        let appended: LayoutRef = try #require(boxLayout.children.last)
        #expect(appended.node.element?.tag == "p")
        #expect(profiler.snapshot()["layout.children.rebuilt"] == nil)
        #expect((profiler.snapshot()["layout.children.appended"]?.count ?? 0) == 1)
        expectIncrementalMatchesFull(page)
    }

    @Test func appendMergesIntoTailingInlineRun() throws {
        let css: String = """
            body { display: block; }
            div { display: block; }
            p { display: block; height: 20px; }
        """
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p id="one">one</p>tail</div>"#,
            rules: css
        )
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let one: ElementRef = try #require(page.firstElement(id: "one"))
        let boxLayout: LayoutRef = try #require(page.firstBlock(in: box))
        let oneLayout: LayoutRef = try #require(page.firstBlock(in: one))
        #expect(boxLayout.children.count == 2)
        page.frame.js = JSRuntime(frame: page.frame)

        page.frame.js.run(
            script: "appendChild",
            code: """
                var box = document.getElementById('box');
                var fresh = document.createElement('span');
                fresh.textContent = ' more';
                box.appendChild(fresh);
            """
        )
        page.frame.rules = CSSParser(css).parse().rules
        profiler.reset()
        page.frame.setNeedsRender()
        page.frame.render()

        #expect(boxLayout.children.count == 2)
        #expect(boxLayout.children[0].id == oneLayout.id)
        let run: LayoutRef = try #require(boxLayout.children.last)
        let extras: [NodeID] = run.blockData.content.extraNodes
        #expect(extras.count == 2)
        #expect(DOMRef(id: extras[1], dom: run.tree.dom).element?.tag == "span")
        #expect(profiler.snapshot()["layout.children.rebuilt"] == nil)
        #expect((profiler.snapshot()["layout.children.appended"]?.count ?? 0) == 1)
        expectIncrementalMatchesFull(page)
    }
}
