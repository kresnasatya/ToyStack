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
        let box: Element = try #require(page.firstElement(id: "box"))
        let oldParent: Element = try #require(page.firstElement(id: "old-parent"))
        let old: any DOMNode = box.children[0]
        let one: any DOMNode = oldParent.children[0]
        let two: any DOMNode = oldParent.children[1]
        page.frame.js = JSRuntime(frame: page.frame)

        let boxHeightBefore: CGFloat = try #require(box.layoutObject).height
        let oldParentHeightBefore: CGFloat = try #require(oldParent.layoutObject).height

        page.frame.js.run(script: "appendChild", code: "document.getElementById('box').appendChild(document.getElementById('one'));")

        #expect(box.children.count == 2)
        #expect(box.children[0] === old)
        #expect(box.children[1] === one)
        #expect(old.parent === box)
        #expect(one.parent === box)
        #expect(oldParent.children.count == 1)
        #expect(oldParent.children[0] === two)
        #expect(two.parent === oldParent)

        page.frame.rules = CSSParser(css).parse().rules
        page.frame.setNeedsRender()
        page.frame.render()

        #expect((box.layoutObject?.height ?? 0) > boxHeightBefore)
        #expect((oldParent.layoutObject?.height ?? 0) < oldParentHeightBefore)
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
        let box: Element = try #require(page.firstElement(id: "box"))
        let one: any DOMNode = box.children[0]
        let two: any DOMNode = box.children[1]
        page.frame.js = JSRuntime(frame: page.frame)

        page.frame.js.run(
            script: "appendChild",
            code: """
                var box = document.getElementById('box');
                box.appendChild(box.children[0]);
            """
        )

        #expect(box.children.count == 2)
        #expect(box.children[0] === two)
        #expect(box.children[1] === one)
        #expect(one.parent === box)
        #expect(two.parent === box)
    }
}
