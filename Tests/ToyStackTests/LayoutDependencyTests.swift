import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutDependencyTests {

    @Test func everyLayoutFieldFreezesItsInputs() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: DocumentLayout = try #require(page.frame.document)

        for object in treeToList(document) {
            for (name, field) in layoutFields(of: object) {
                #expect(
                    field.frozenDependencies,
                    "\(type(of: object)).\(name) is not frozen"
                )
            }
        }
    }

    @Test func widthFlowsDownAndHeightFlowsBackUp() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: DocumentLayout = try #require(page.frame.document)
        let root: BlockLayout = try #require(document.children.first as? BlockLayout)
        let body: BlockLayout = try #require(root.children.first as? BlockLayout)
        let box: BlockLayout = try #require(body.children.first as? BlockLayout)
        let paragraph: BlockLayout = try #require(box.children.first as? BlockLayout)
        let line: LineLayout = try #require(paragraph.children.first as? LineLayout)

        #expect(document.widthField.containsInvalidation(root.widthField))
        #expect(root.widthField.containsInvalidation(body.widthField))
        #expect(box.zoomField.containsInvalidation(paragraph.zoomField))
        #expect(paragraph.widthField.containsInvalidation(line.widthField))
        #expect(line.heightField.containsInvalidation(paragraph.heightField))
        #expect(root.heightField.containsInvalidation(document.heightField))
    }

    @Test func fontFieldOwnsTheParentStyleInputs() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let paragraph: Element = try #require(page.firstElement(tag: "p"))
        let block: BlockLayout = try #require(paragraph.layoutObject as? BlockLayout)
        let text: TextLayout = try #require(
            treeToList(block).compactMap({ $0 as? TextLayout }).first
        )

        #expect(paragraph.style.field("font-size").containsInvalidation(text.fontField))
        #expect(paragraph.style.field("font-style").containsInvalidation(text.fontField))
        #expect(paragraph.style.field("font-weight").containsInvalidation(text.fontField))
        #expect(paragraph.style.field("font-family").containsInvalidation(text.fontField))
    }

    @Test func anUndeclaredEdgeIsAbsentFromTheGraph() {
        let source: ProtectedField<CGFloat> = ProtectedField("source", cleanValue: 1)
        let missing: ProtectedField<CGFloat> = ProtectedField("missing", cleanValue: 1)
        let declared: ProtectedField<CGFloat> = ProtectedField("declared", cleanValue: 1)

        missing.setDependencies([])
        declared.setDependencies([source])

        #expect(!source.containsInvalidation(missing))
        #expect(source.containsInvalidation(declared))
    }
}

@MainActor
private func makeDependencyPage() -> LayoutTestPage {
    return LayoutTestPage(
        html: """
            <div id="box"><p id="p">one <b>two</b> three</p></div>
            <p id="controls"><button>Go</button><input type="text"><input type="checkbox"><img width="20" height="10"><iframe width="100" height="50"></iframe><canvas width="30" height="20"></canvas></p>
            """,
        rules: """
            html { width: 600px; }
            body { display: block; }
            div { display: block; }
            p { display: block; }
            """
    )
}
