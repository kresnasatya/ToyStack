import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutInputsTests {

    @Test func blockChildIsFoundAmongInlineSiblings() throws {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<div id="mixed">one <b>two</b><p>three</p></div><div id="flat">one <b>two</b></div>"#,
            rules: """
                body { display: block; }
                div { display: block; }
                p { display: block; }
            """
        )
        let mixed: ElementRef = try #require(page.firstElement(id: "mixed"))
        let flat: ElementRef = try #require(page.firstElement(id: "flat"))
        let inputs: LayoutInputs = page.tree.inputs

        #expect(inputs.hasBlockChild(mixed.id))
        #expect(!inputs.hasBlockChild(flat.id))
    }

    @Test func nodeOutsideTheInputsHasNoBlockChild() {
        let page: LayoutTestPage = LayoutTestPage(
            html: #"<p>one</p>"#,
            rules: """
                body { display: block; }
                p { display: block; }
            """
        )

        #expect(!page.tree.inputs.hasBlockChild(NodeID(raw: UInt32.max)))
    }
}
