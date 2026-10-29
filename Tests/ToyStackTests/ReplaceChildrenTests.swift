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
}
