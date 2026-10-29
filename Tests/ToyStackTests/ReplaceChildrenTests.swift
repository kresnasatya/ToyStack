import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct ReplaceChildrenTests {

    @Test func clearsChildrenAndInvalidates() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p>one</p><p>two</p></div><p id="after">after</p>"#,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                p { display: block; }
                """
        )
        let box: Element = try #require(page.firstElement(tag: "div"))
        page.frame.js = JSRuntime(frame: page.frame)

        let removed: [any DOMNode] = box.children
        let heightBefore: CGFloat = try #require(box.layoutObject).height

        page.frame.js.run(script: "replaceChildren", code: "document.getElementById('box').replaceChildren()")

        #expect(box.children.isEmpty)
        #expect(removed.count == 2)
        #expect(removed.allSatisfy({ $0.parent == nil }))
        #expect(page.frame.nodes.style.isDirty)

        page.frame.render()
        #expect((box.layoutObject?.height ?? 0) < heightBefore)
    }

    @Test func transferChildrenFromOtherParentsInOrder() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: """
                <div id="box"><p id="old">old</p></div>
                <div id="donor"><p id="one">one</p><p id="two">two</p></div>
            """,
            rules: """
                html { width: 600px; }
                body { display: block; }
                div { display: block; }
                p { display: block; }
            """
        )
        let box: Element = try #require(page.firstElement(id: "box"))
        let donor: Element = try #require(page.firstElement(id: "donor"))
        let old: any DOMNode = try #require(box.children.first)
        let one: any DOMNode = donor.children[0]
        let two: any DOMNode = donor.children[1]
        page.frame.js = JSRuntime(frame: page.frame)

        let boxHeightBefore: CGFloat = try #require(box.layoutObject).height
        let donorHeightBefore: CGFloat = try #require(donor.layoutObject).height

        page.frame.js.run(
            script: "replaceChildren",
            code: """
                var donor = document.getElementById('donor');
                document.getElementById('box').replaceChildren(donor.children[0], donor.children[1]);
            """)

        #expect(old.parent == nil)
        #expect(donor.children.isEmpty)
        #expect(box.children.count == 2)
        #expect(box.children[0] === one)
        #expect(box.children[1] === two)
        #expect(one.parent === box)
        #expect(two.parent === box)
        #expect(page.frame.nodes.style.isDirty)

        page.frame.render()
        #expect((box.layoutObject?.height ?? 0) > boxHeightBefore)
        #expect((donor.layoutObject?.height ?? 0) < donorHeightBefore)
    }

    @Test func adoptsDetachedChildAndMovesRepeatedChildLast() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="box"><p id="one"></p><p id="two">two</p></div>"#,
            rules: """
                html { width: 600px; }
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
            script: "replaceChildren",
            code: """
                var box = document.getElementById('box');
                var made = document.createElement('p');
                made.textContent = 'made';
                box.replaceChildren(box.children[1], box.children[0], made, made);
            """
        )

        let identifiers: Set<ObjectIdentifier> = Set(box.children.map({ ObjectIdentifier($0) }))
        #expect(box.children.count == 3)
        #expect(identifiers.count == 3)
        #expect(box.children[0] === two)
        #expect(box.children[1] === one)
        #expect(box.children[2] !== one)
        #expect(box.children[2] !== two)
        #expect(box.children[2].parent === box)
    }
}
