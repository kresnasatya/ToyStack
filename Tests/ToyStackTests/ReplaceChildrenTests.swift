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
        let box: ElementRef = try #require(page.firstElement(tag: "div"))
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        let removed: [DOMRef] = box.children
        let heightBefore: CGFloat = try #require(box.ref.layout).height

        page.frame.js.run(script: "replaceChildren", code: "document.getElementById('box').replaceChildren()")

        #expect(box.children.isEmpty)
        #expect(removed.count == 2)
        #expect(removed.allSatisfy({ $0.parent == nil }))
        #expect(page.frame.nodes.style.isDirty)

        page.frame.render()
        #expect((page.ref(of: box).layout?.height ?? 0) < heightBefore)
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
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let donor: ElementRef = try #require(page.firstElement(id: "donor"))
        let old: NodeID = try #require(box.children.first).id
        let one: NodeID = donor.children[0].id
        let two: NodeID = donor.children[1].id
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        let boxHeightBefore: CGFloat = try #require(page.ref(of: box).layout).height
        let donorHeightBefore: CGFloat = try #require(page.ref(of: donor).layout).height

        page.frame.js.run(
            script: "replaceChildren",
            code: """
                var donor = document.getElementById('donor');
                document.getElementById('box').replaceChildren(donor.children[0], donor.children[1]);
            """)

        #expect(page.frame.dom.parent(of: old) == nil)
        #expect(donor.children.isEmpty)
        #expect(box.children.count == 2)
        #expect(box.children[0].id == one)
        #expect(box.children[1].id == two)
        #expect(page.frame.dom.parent(of: one) == box.id)
        #expect(page.frame.dom.parent(of: two) == box.id)
        #expect(page.frame.nodes.style.isDirty)

        page.frame.render()
        #expect((page.ref(of: box).layout?.height ?? 0) > boxHeightBefore)
        #expect((page.ref(of: donor).layout?.height ?? 0) < donorHeightBefore)
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
        let box: ElementRef = try #require(page.firstElement(id: "box"))
        let one: NodeID = box.children[0].id
        let two: NodeID = box.children[1].id
        page.frame.setJSRuntime(JSRuntime(frame: page.frame))

        page.frame.js.run(
            script: "replaceChildren",
            code: """
                var box = document.getElementById('box');
                var made = document.createElement('p');
                made.textContent = 'made';
                box.replaceChildren(box.children[1], box.children[0], made, made);
            """
        )

        let identifiers: Set<NodeID> = Set(box.children.map({ $0.id }))
        #expect(box.children.count == 3)
        #expect(identifiers.count == 3)
        #expect(box.children[0].id == two)
        #expect(box.children[1].id == one)
        #expect(box.children[2].id != one)
        #expect(box.children[2].id != two)
        #expect(box.children[2].parent?.id == box.id)
    }
}
