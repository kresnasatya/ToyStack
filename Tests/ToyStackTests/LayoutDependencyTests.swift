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

    // MARK: - Static input table (D1)

    @Test func staticTableMatchesTheFrozenGraph() throws {
        try expectTableMatchesIndex(makeDependencyPage())
    }

    @Test func staticTableMatchesTheFrozenGraphForEmbeds() throws {
        try expectTableMatchesIndex(makeEmbedDependencyPage())
    }

    @Test func rebuildFromTableReproducesTheCleanGraph() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)
        let before: [FieldKey: Set<FieldKey>] = dependencySnapshot(document)

        document.dependencies.rebuild(from: document)

        #expect(dependencySnapshot(document) == before)
        try expectTableMatchesIndex(document)
    }

    @Test func removedChildContributesNoEdgesAfterRebuild() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)
        let p: ElementRef = try #require(page.firstElement(id: "p"))
        let line: LayoutRef = try #require(page.firstLine(in: p))
        let removed: LayoutRef = try #require(line.children.first)

        document.removeSubtree(removed.id)
        document.dependencies.rebuild(from: document)

        for field in LayoutField.allCases {
            #expect(
                document.dependencies.fieldKeys(for: .layout(removed.id, field), in: document).isEmpty,
                "removed node still owns \(field.rawValue) dependents"
            )
        }
        for id in document.liveIDs {
            for field in LayoutField.allCases where document.isUsed(field, at: id) {
                let inputs: Set<FieldKey> = document.dependencies.fieldKeys(
                    for: .layout(id, field),
                    in: document
                )
                #expect(
                    !inputs.contains(where: { isEdgeTo($0, removed.id) }),
                    "\(field.rawValue) still reads removed node"
                )
            }
        }
    }

    @Test func tableAnswersEveryFieldCase() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)

        for ref in treeToList(document.root) {
            for field in LayoutField.allCases {
                let keys: [FieldKey] = LayoutInputTable.inputs(
                    for: ref.id,
                    field: field,
                    in: document
                )
                if document.isUsed(field, at: ref.id) {
                    #expect(document.isFrozen(field, at: ref.id))
                    #expect(document.dependencies.fieldKeys(for: .layout(ref.id, field), in: document) == Set(keys))
                }
            }
        }
    }
}

@MainActor
private func expectTableMatchesIndex(_ page: LayoutTestPage) throws {
    let document: LayoutTree = try #require(page.frame.document)
    try expectTableMatchesIndex(document)
}

@MainActor
private func expectTableMatchesIndex(_ document: LayoutTree) throws {
    for ref in treeToList(document.root) {
        for field in LayoutField.allCases where document.isUsed(field, at: ref.id) {
            let expected: Set<FieldKey> = Set(
                LayoutInputTable.inputs(for: ref.id, field: field, in: document)
            )
            let actual: Set<FieldKey> = document.dependencies.fieldKeys(
                for: .layout(ref.id, field),
                in: document
            )
            #expect(
                actual == expected,
                "\(ref.kind).\(field.rawValue) #\(ref.id.raw) differs from input table"
            )
        }
    }
}

@MainActor
private func dependencySnapshot(_ tree: LayoutTree) -> [FieldKey: Set<FieldKey>] {
    var snapshot: [FieldKey: Set<FieldKey>] = [:]
    for id in tree.liveIDs {
        for field in LayoutField.allCases where tree.isUsed(field, at: id) {
            let key: FieldKey = .layout(id, field)
            snapshot[key] = tree.dependencies.fieldKeys(for: key, in: tree)
        }
    }
    return snapshot
}

private func isEdgeTo(_ key: FieldKey, _ id: LayoutID) -> Bool {
    if case .layout(let owner, _) = key, owner == id { return true }
    return false
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

@MainActor
private func makeEmbedDependencyPage() -> LayoutTestPage {
    return LayoutTestPage(
        html: """
            <div><p id="embeds">before <img width="40" height="20"> mid <iframe width="100" height="50"></iframe> <canvas width="30" height="20"></canvas></p>
            <p id="controls2"><button>Go</button> <input type="text"> <input type="checkbox"></p>
            </div>
            """,
        rules: """
            html { width: 700px; }
            body { display: block; }
            div { display: block; }
            p { display: block; }
            """
    )
}
