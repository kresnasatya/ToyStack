import Foundation
import Testing

@testable import Engine

@Suite(.serialized)
@MainActor
struct StyleFieldsTests {

    @Test func sameValueDoesNotMark() {
        let (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        tree.consumeStyleChanges()
        tree.setFieldClean(.width, 10, for: block.id)

        style.set(.length(10), for: .width)
        tree.consumeStyleChanges()
        #expect(!tree.isDirty(.width, at: block.id))
    }

    @Test func differentValueMarks() {
        let (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        tree.consumeStyleChanges()
        tree.setFieldClean(.width, 10, for: block.id)

        style.set(.length(20), for: .width)
        tree.consumeStyleChanges()
        #expect(tree.isDirty(.width, at: block.id))
    }

    @Test func absentPropertyStillMarks() {
        let (style, tree, block) = makeStyleFixture()
        tree.setFieldClean(.width, 0, for: block.id)
        #expect(style.computed.box.size.width == nil)

        style.set(.length(20), for: .width)
        tree.consumeStyleChanges()

        #expect(tree.isDirty(.width, at: block.id))
    }

    @Test func removingAPropertyMarksTheLayoutField() {
        let (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        tree.consumeStyleChanges()
        tree.setFieldClean(.width, 10, for: block.id)

        style.apply(["height": "5px"])
        tree.consumeStyleChanges()
        #expect(tree.isDirty(.width, at: block.id))
    }

    @Test func paintOnlyChangeDoesNotMark() {
        let (style, tree, block) = makeStyleFixture()
        tree.setFieldClean(.width, 10, for: block.id)

        style.apply(["color": "red"])
        tree.consumeStyleChanges()

        #expect(!tree.isDirty(.width, at: block.id))
    }

    @Test func identicalApplyDoesNotMark() {
        let (style, tree, block) = makeStyleFixture()
        style.apply(["width": "10px"])
        tree.consumeStyleChanges()
        tree.setFieldClean(.width, 10, for: block.id)

        profiler.reset()
        style.apply(["width": "10px"])
        tree.consumeStyleChanges()

        #expect(!tree.isDirty(.width, at: block.id))
        #expect((profiler.snapshot()["style.fields.changed"]?.count ?? 0) == 0)
    }

    @Test func mutateMarksTheLayoutField() {
        let (style, tree, block) = makeStyleFixture()
        tree.setFieldClean(.width, 10, for: block.id)

        style.mutate { $0.box.size.width = 30 }
        tree.consumeStyleChanges()

        #expect(tree.isDirty(.width, at: block.id))
    }

    @Test func aRevisionIsAppliedOnce() {
        let (style, tree, block) = makeStyleFixture()
        style.set(.length(20), for: .width)
        tree.consumeStyleChanges()
        tree.setFieldClean(.width, 20, for: block.id)

        tree.consumeStyleChanges()

        #expect(!tree.isDirty(.width, at: block.id))
    }

    @Test func applyStoresTypedValues() {
        let style = StyleFields()
        #expect(style.computed == .initial)

        style.apply(["width": "10px", "height": "5px"])
        #expect(style.computed.box.size.width == 10)
        #expect(style.computed.box.size.height == 5)

        style.apply(["width": "10px"])
        #expect(style.computed.box.size.height == nil)
    }

    @Test func rebuildDoesNotDuplicateDependents() {
        let (_, tree, _) = makeStyleFixture()
        let key: FieldKey = .style(tree.dom.root, .width)

        tree.dependencies.rebuild(from: tree)
        let first: Int = tree.dependencies.count(of: key)
        tree.dependencies.rebuild(from: tree)

        #expect(first == 1)
        #expect(tree.dependencies.count(of: key) == 1)
    }

    @Test func applyBumpsRevisionOnceWhenValuesChange() {
        let style: StyleFields = StyleFields()
        let before: UInt64 = style.revision

        style.apply(["width": "10px", "height": "5px"])

        #expect(style.revision == before + 1)
    }

    @Test func identicalApplyDoesNotBumpRevision() {
        let style: StyleFields = StyleFields()
        style.apply(["width": "10px"])
        let before: UInt64 = style.revision

        style.apply(["width": "10px"])

        #expect(style.revision == before)
    }

    @Test func typedWriteBumpsRevisionOnlyWhenValueChanges() {
        let style: StyleFields = StyleFields()
        let before: UInt64 = style.revision

        style.set(.length(10), for: .width)
        #expect(style.revision == before + 1)

        let afterFirstWrite: UInt64 = style.revision
        style.set(.length(10), for: .width)
        #expect(style.revision == afterFirstWrite)

        style.set(.length(20), for: .width)
        #expect(style.revision == afterFirstWrite + 1)
    }

    @Test func removingAValueBumpsRevision() {
        let style: StyleFields = StyleFields()
        style.apply(["width": "10px", "height": "5px"])
        let before: UInt64 = style.revision

        style.apply(["width": "10px"])

        #expect(style.revision == before + 1)
    }
}

@MainActor
private func makeStyleFixture() -> (StyleFields, LayoutTree, LayoutRef) {
    let dom: DOMTree = DOMTree()
    let tree: LayoutTree = LayoutTree(dom: dom)
    let blockID: LayoutID = tree.append(
        kind: .block(BlockData()),
        dom: dom.root,
        parent: tree.root.id,
        previous: nil
    )
    for field in [LayoutField.zoom, .x, .y, .width, .inlineContent, .children] {
        tree.markUsed(field, at: blockID)
    }
    let block: LayoutRef = LayoutRef(id: blockID, tree: tree)
    tree.dependencies.rebuild(from: tree)
    return (dom.style(of: dom.root), tree, block)
}
