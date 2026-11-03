import CoreGraphics
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct LayoutDependencyTests {

    @Test func unusedFieldsHaveNoEdges() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)

        for object in treeToList(document.root) {
            for field in LayoutField.allCases where !document.isUsed(field, at: object.id) {
                #expect(
                    document.dependencies
                        .fieldKeys(for: .layout(object.id, field))
                        .isEmpty,
                    "\(object.kind).\(field.rawValue) is unused but owns dependents"
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

        #expect(depends(root, on: .layout(document.root.id, .width), in: document))
        #expect(depends(body, on: .layout(root.id, .width), in: document))
        #expect(depends(paragraph, on: .layout(box.id, .zoom), in: document, field: .zoom))
        #expect(depends(line, on: .layout(paragraph.id, .width), in: document))
        #expect(depends(paragraph, on: .layout(line.id, .height), in: document, field: .height))
        #expect(depends(document.root, on: .layout(root.id, .height), in: document, field: .height))
    }

    @Test func fontFieldOwnsTheParentStyleInputs() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let paragraph: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutRef = try #require(page.firstBlock(in: paragraph))
        let text: LayoutRef = try #require(
            treeToList(block).first(where: { $0.isText })
        )
        let document: LayoutTree = try #require(page.frame.document)
        let inputs: Set<FieldKey> = document.dependencies.fieldKeys(
            for: .layout(text.id, .font)
        )

        #expect(inputs.contains(.style(paragraph.id, .fontSize)))
        #expect(inputs.contains(.style(paragraph.id, .fontStyle)))
        #expect(inputs.contains(.style(paragraph.id, .fontWeight)))
        #expect(inputs.contains(.style(paragraph.id, .fontFamily)))
    }

    @Test func anUndeclaredEdgeIsAbsentFromTheGraph() {
        let dom: DOMTree = DOMTree()
        let document: LayoutTree = LayoutTree(dom: dom)
        document.dependencies.rebuild(from: document)
        let root: LayoutID = document.root.id

        let widthInputs: Set<FieldKey> = document.dependencies
            .fieldKeys(for: .layout(root, .width))
        #expect(widthInputs == [.layout(root, .zoom)])
        #expect(!widthInputs.contains(.layout(root, .x)))
        #expect(!widthInputs.contains(.layout(root, .y)))
    }

    @Test func fieldWriteMarksItsDependents() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let document: LayoutTree = try #require(page.frame.document)
        let root: LayoutRef = try #require(document.root.children.first)

        document.setFieldClean(.width, 600, for: document.root.id)
        document.setFieldClean(.width, root.width, for: root.id)
        document.setField(.width, 500, for: document.root.id)

        #expect(document.isDirty(.width, at: root.id))
    }

    @Test func widthMarksLinesButNotInlineContent() throws {
        let page: LayoutTestPage = makeDependencyPage()
        let p: ElementRef = try #require(page.firstElement(tag: "p"))
        let block: LayoutRef = try #require(page.firstBlock(in: p))
        let line: LayoutRef = try #require(page.firstLine(in: p))
        let document: LayoutTree = try #require(page.frame.document)

        let widthInputs: Set<FieldKey> = document.dependencies.fieldKeys(
            for: .layout(block.id, .width)
        )
        #expect(!widthInputs.contains(.layout(block.id, .children)))
        #expect(!widthInputs.contains(.layout(block.id, .inlineContent)))

        let childInputs: Set<FieldKey> = document.dependencies.fieldKeys(
            for: .layout(block.id, .children)
        )
        #expect(childInputs.contains(.layout(block.id, .inlineContent)))

        let heightInputs: Set<FieldKey> = document.dependencies.fieldKeys(
            for: .layout(block.id, .height)
        )
        #expect(heightInputs.contains(.layout(line.id, .height)))

        let contentInputs: Set<FieldKey> = document.dependencies.fieldKeys(
            for: .layout(block.id, .inlineContent)
        )
        #expect(contentInputs.contains(.style(p.id, .fontSize)))

        let lineWidthInputs: Set<FieldKey> = document.dependencies.fieldKeys(
            for: .layout(line.id, .width)
        )
        #expect(lineWidthInputs.contains(.layout(block.id, .width)))
    }

    // MARK: - Static input table (D1)

    @Test func staticTableMatchesTheIndex() throws {
        try expectTableMatchesIndex(makeDependencyPage())
    }

    @Test func staticTableMatchesTheIndexForEmbeds() throws {
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
                document.dependencies
                    .fieldKeys(for: .layout(removed.id, field))
                    .isEmpty,
                "removed node still owns \(field.rawValue) dependents"
            )
        }
        for id in document.liveIDs {
            for field in LayoutField.allCases where document.isUsed(field, at: id) {
                let inputs: Set<FieldKey> = document.dependencies.fieldKeys(
                    for: .layout(id, field)
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
                    #expect(
                        document.dependencies.fieldKeys(for: .layout(ref.id, field))
                            == Set(keys)
                    )
                }
            }
        }
    }
}

@MainActor
private func depends(
    _ ref: LayoutRef,
    on key: FieldKey,
    in tree: LayoutTree,
    field: LayoutField = .width
) -> Bool {
    return tree.dependencies.fieldKeys(for: .layout(ref.id, field)).contains(key)
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
                for: .layout(ref.id, field)
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
            snapshot[key] = tree.dependencies.fieldKeys(for: key)
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
