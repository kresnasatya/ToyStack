import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutDependencyTests {

    @Test func everyLayoutFieldFreezesItsInputs() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)

        for object in treeToList(document.root) {
            for (name, field) in layoutFields(of: object) {
                #expect(
                    field.frozenDependencies,
                    "\(object.kind).\(name) is not frozen"
                )
            }
        }
    }

    @Test func widthFlowsDownAndHeightFlowsBackUp() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)
        let root: LayoutRef = try #require(document.root.children.first)
        let body: LayoutRef = try #require(root.children.first)
        let box: LayoutRef = try #require(body.children.first)
        let paragraph: LayoutRef = try #require(box.children.first)
        let line: LayoutRef = try #require(paragraph.children.first)

        #expect(document.root.widthField.containsInvalidation(root.widthField))
        #expect(root.widthField.containsInvalidation(body.widthField))
        #expect(box.zoomField.containsInvalidation(paragraph.zoomField))
        #expect(paragraph.widthField.containsInvalidation(line.widthField))
        #expect(line.heightField.containsInvalidation(paragraph.heightField))
        #expect(root.heightField.containsInvalidation(document.root.heightField))
    }

    @Test func fontFieldOwnsTheParentStyleInputs() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutRef = try #require(page.firstBlock(in: paragraph))
        let text: LayoutRef = try #require(
            treeToList(block).first(where: { $0.isText })
        )

        #expect(paragraph.style.field(.fontSize).containsInvalidation(text.fontField))
        #expect(paragraph.style.field(.fontStyle).containsInvalidation(text.fontField))
        #expect(paragraph.style.field(.fontWeight).containsInvalidation(text.fontField))
        #expect(paragraph.style.field(.fontFamily).containsInvalidation(text.fontField))
    }

    @Test func anUndeclaredEdgeIsAbsentFromTheGraph() {
        let dom: DOMTree = DOMTree()
        let document: LayoutTree = LayoutTree(dom: dom)

        let source = document.root.xField
        let missing = document.root.yField
        let declared = document.root.widthField

        missing.setDependencies([])
        declared.setDependencies([source])

        #expect(!source.containsInvalidation(missing))
        #expect(source.containsInvalidation(declared))
    }

    @Test func removingALayoutEdgeRemovesTheDependent() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)
        let root: LayoutRef = try #require(document.root.children.first)

        let key: FieldKey = .layout(root.id, .ascent)
        root.tree.dependencies.add(root.widthField.ref, for: key)
        #expect(root.tree.dependencies.count(of: key) == 1)

        root.tree.dependencies.remove(root.widthField.ref, for: key)
        #expect(root.tree.dependencies.count(of: key) == 0)
    }

    @Test func widthMarksLinesButNotInlineContent() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutRef = try #require(page.firstBlock(in: p))

        #expect(!block.widthField.containsInvalidation(block.childrenField))
        #expect(!block.widthField.containsInvalidation(block.inlineContentField))
        #expect(block.inlineContentField.containsInvalidation(block.childrenField))
        #expect(p.style.field(.fontSize).containsInvalidation(block.inlineContentField))
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
